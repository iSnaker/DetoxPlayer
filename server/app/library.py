import json
import os
import sqlite3
import threading
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path

from mutagen import File


def now():
    return datetime.now(timezone.utc).isoformat()


class LibraryError(Exception):
    pass


class SourceRemoved(Exception):
    pass


def readable_tag(value: str, path: Path) -> str:
    """Recover legacy CP1251 bytes mislabeled as Latin-1, only with path evidence.

    Never rewrite audio tags or guess from Cyrillic-looking output alone: legitimate
    accented Latin text can also decode as CP1251. The entire recovered tag must
    occur in a filename or directory component, ignoring punctuation and case.
    """
    def normalized(text):
        return ''.join(c for c in text.casefold() if c.isalnum())

    evidence = [normalized(part) for part in path.parts]
    for encoding in ('latin1', 'cp1252'):
        try:
            candidate = value.encode(encoding).decode('cp1251')
        except UnicodeError:
            continue
        if candidate == value or sum('а' <= c <= 'я' or c == 'ё' for c in candidate.casefold()) < 3:
            continue
        match = normalized(candidate)
        if any(match in part for part in evidence):
            return candidate
    return value


class Library:
    def __init__(self, data: Path, roots: list[Path], *, recover_scans=True):
        data.mkdir(parents=True, exist_ok=True)
        self.database = data / 'library.sqlite3'
        self.roots = [p.resolve() for p in roots]
        self.lock = threading.RLock()
        self.job = None
        self.removed_sources = set()
        with self.connect() as db:
            db.executescript('''
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS sources (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL,
                    active INTEGER NOT NULL DEFAULT 1, scanned_at TEXT, error TEXT
                );
                CREATE TABLE IF NOT EXISTS tracks (
                    id TEXT PRIMARY KEY, source_id TEXT NOT NULL REFERENCES sources(id),
                    path TEXT NOT NULL, folder TEXT NOT NULL, filename TEXT NOT NULL,
                    title TEXT NOT NULL, artist TEXT NOT NULL, album TEXT NOT NULL,
                    duration REAL, size INTEGER NOT NULL, mtime_ns INTEGER NOT NULL,
                    error TEXT, available INTEGER NOT NULL DEFAULT 1,
                    UNIQUE(source_id, path)
                );
                CREATE INDEX IF NOT EXISTS tracks_source ON tracks(source_id, available);
                CREATE TABLE IF NOT EXISTS folders (
                    source_id TEXT NOT NULL REFERENCES sources(id), path TEXT NOT NULL,
                    PRIMARY KEY(source_id, path)
                );
                CREATE TABLE IF NOT EXISTS scans (
                    id TEXT PRIMARY KEY, mode TEXT NOT NULL, status TEXT NOT NULL,
                    started_at TEXT NOT NULL, finished_at TEXT, processed INTEGER NOT NULL DEFAULT 0,
                    errors TEXT NOT NULL DEFAULT '[]'
                );
                CREATE TABLE IF NOT EXISTS access_keys (
                    id TEXT PRIMARY KEY, name TEXT NOT NULL, digest TEXT NOT NULL,
                    created_at TEXT NOT NULL, revoked_at TEXT
                );
                CREATE INDEX IF NOT EXISTS access_keys_digest ON access_keys(digest);
                CREATE TABLE IF NOT EXISTS key_usage (
                    key_id TEXT PRIMARY KEY REFERENCES access_keys(id), last_used_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS client_sessions (
                    digest TEXT PRIMARY KEY, key_id TEXT NOT NULL REFERENCES access_keys(id),
                    expires_at REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS client_sessions_key ON client_sessions(key_id);
            ''')
            # Only the scanner process owns recovery. Starting the separate client API
            # must not mark a live administrative scan as interrupted.
            if recover_scans:
                db.execute("UPDATE scans SET status='interrupted', finished_at=? WHERE status='running'", (now(),))

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.database, timeout=30)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        db.create_function('casefold', 1, lambda value: (value or '').casefold(), deterministic=True)
        try:
            with db:
                yield db
        finally:
            db.close()

    def allowed(self, path: str) -> Path:
        candidate = Path(path).resolve()
        if not any(candidate == root or root in candidate.parents for root in self.roots):
            raise LibraryError('Папка находится вне разрешённых каталогов Docker.')
        return candidate

    def browse(self, path: str | None):
        if path is None:
            return {'path': None, 'parent': None, 'folders': [
                {'name': str(root), 'path': str(root), 'available': root.is_dir()}
                for root in self.roots
            ]}
        folder = self.allowed(path)
        if not folder.is_dir():
            raise LibraryError('Папка недоступна. Проверьте диск и монтирование Docker.')
        try:
            children = []
            for child in folder.iterdir():
                if not child.is_symlink() and child.is_dir():
                    try:
                        self.allowed(str(child))
                    except (OSError, LibraryError):
                        continue
                    children.append({'name': child.name, 'path': str(child), 'available': True})
        except OSError as exc:
            raise LibraryError('Не удалось прочитать папку.') from exc
        parent = None if folder in self.roots else str(folder.parent)
        return {'path': str(folder), 'parent': parent, 'folders': sorted(children, key=lambda x: x['name'].casefold())}

    def sources(self):
        with self.connect() as db:
            rows = db.execute('''SELECT s.*, COUNT(t.id) AS tracks FROM sources s
                LEFT JOIN tracks t ON t.source_id=s.id AND t.available=1
                WHERE s.active=1 GROUP BY s.id ORDER BY s.name''').fetchall()
        return [dict(row) | {'available': Path(row['path']).is_dir()} for row in rows]

    def add_source(self, name: str, path: str):
        folder = self.allowed(path)
        if not folder.is_dir():
            raise LibraryError('Папка недоступна.')
        with self.lock, self.connect() as db:
            if self.job:
                raise LibraryError('Дождитесь завершения сканирования перед добавлением папки.')
            for row in db.execute('SELECT path FROM sources WHERE active=1'):
                other = Path(row['path']).resolve()
                if folder == other or folder in other.parents or other in folder.parents:
                    raise LibraryError('Папка уже добавлена или пересекается с другим источником.')
            source_id = uuid.uuid4().hex
            db.execute('INSERT INTO sources(id,name,path) VALUES(?,?,?)', (source_id, name.strip() or folder.name or str(folder), str(folder)))
        return source_id

    def remove_source(self, source_id: str):
        with self.lock, self.connect() as db:
            if not db.execute('SELECT 1 FROM sources WHERE id=? AND active=1', (source_id,)).fetchone():
                raise LibraryError('Источник не найден.')
            db.execute('UPDATE sources SET active=0 WHERE id=?', (source_id,))
            db.execute('UPDATE tracks SET available=0 WHERE source_id=?', (source_id,))
            self.removed_sources.add(source_id)
            # A scan checks active again inside its commit transaction; removed sources cannot reappear.

    def start_scan(self, source_id: str | None, reset: bool = False):
        with self.lock:
            if self.job:
                raise LibraryError('Сканирование уже выполняется.')
            sources = self.sources()
            if source_id:
                sources = [s for s in sources if s['id'] == source_id]
            if not sources:
                raise LibraryError('Нет папок для сканирования.')
            scan_id = uuid.uuid4().hex
            with self.connect() as db:
                db.execute('INSERT INTO scans(id,mode,status,started_at) VALUES(?,?,?,?)', (scan_id, 'reset' if reset else 'rescan', 'running', now()))
            self.job = scan_id
            worker = threading.Thread(target=self._scan, args=(scan_id, sources, reset), daemon=True)
            worker.start()
            return scan_id

    def latest_scan(self):
        with self.connect() as db:
            row = db.execute('SELECT * FROM scans ORDER BY rowid DESC LIMIT 1').fetchone()
        if not row:
            return None
        result = dict(row)
        result['errors'] = json.loads(result['errors'])
        return result

    @staticmethod
    def metadata(path: Path):
        values = {'title': path.stem, 'artist': 'Неизвестный исполнитель', 'album': '', 'duration': None, 'error': None}
        try:
            audio = File(path, easy=True)
            if audio is None:
                raise ValueError('Формат MP3 не распознан')
            for field in ('title', 'artist', 'album'):
                tag = audio.get(field, [])
                if tag and str(tag[0]).strip():
                    values[field] = readable_tag(str(tag[0]).strip(), path)
            values['duration'] = audio.info.length
        except Exception:
            values['error'] = 'Не удалось прочитать MP3 или его теги'
        return values

    def _collect(self, source, reset, progress):
        root = self.allowed(source['path'])
        if not root.is_dir():
            raise LibraryError('Папка недоступна; прежний каталог сохранён.')
        with self.connect() as db:
            previous = {r['path']: dict(r) for r in db.execute('SELECT * FROM tracks WHERE source_id=?', (source['id'],))}
        result, folders = [], []

        def walk_error(error):
            raise LibraryError('Не удалось прочитать часть папок; прежний каталог источника сохранён.') from error

        for parent, dirs, files in os.walk(root, onerror=walk_error, followlinks=False):
            if source['id'] in self.removed_sources:
                raise SourceRemoved()
            folders.append(Path(parent).relative_to(root).as_posix())
            dirs[:] = sorted(d for d in dirs if not Path(parent, d).is_symlink())
            for name in sorted(files):
                if source['id'] in self.removed_sources:
                    raise SourceRemoved()
                file = Path(parent, name)
                if file.suffix.lower() != '.mp3' or file.is_symlink():
                    continue
                self.allowed(str(file))
                if root not in file.resolve().parents:
                    raise LibraryError('Обнаружен файл за пределами источника.')
                stat = file.stat()
                relative = file.relative_to(root).as_posix()
                old = previous.get(relative)
                if old and not reset and old['size'] == stat.st_size and old['mtime_ns'] == stat.st_mtime_ns:
                    item = old | {'available': 1}
                else:
                    item = self.metadata(file) | {
                        'id': old['id'] if old else uuid.uuid4().hex,
                        'source_id': source['id'], 'path': relative,
                        'folder': file.relative_to(root).parent.as_posix(), 'filename': name,
                        'size': stat.st_size, 'mtime_ns': stat.st_mtime_ns, 'available': 1,
                    }
                result.append(item)
                progress(item)
        if not root.is_dir():
            raise LibraryError('Папка стала недоступна; прежний каталог сохранён.')
        return result, folders

    def _apply(self, db, source, tracks, folders):
        if not db.execute('SELECT 1 FROM sources WHERE id=? AND active=1', (source['id'],)).fetchone():
            return
        db.execute('DELETE FROM folders WHERE source_id=?', (source['id'],))
        db.executemany('INSERT INTO folders(source_id,path) VALUES(?,?)', [(source['id'], folder) for folder in folders])
        db.execute('UPDATE tracks SET available=0 WHERE source_id=?', (source['id'],))
        columns = ('id', 'source_id', 'path', 'folder', 'filename', 'title', 'artist', 'album', 'duration', 'size', 'mtime_ns', 'error', 'available')
        db.executemany('INSERT INTO tracks VALUES(' + ','.join('?' for _ in columns) + ') ON CONFLICT(source_id,path) DO UPDATE SET ' + ','.join(f'{c}=excluded.{c}' for c in columns if c not in ('id','source_id','path')), [tuple(t[c] for c in columns) for t in tracks])
        db.execute('UPDATE sources SET scanned_at=?, error=NULL WHERE id=?', (now(), source['id']))

    def _scan(self, scan_id, sources, reset):
        processed, issues, staged = 0, [], []
        fatal = False

        def progress(item):
            nonlocal processed
            processed += 1
            if item['error'] and len(issues) < 100:
                issues.append({'source_id': item['source_id'], 'path': item['path'], 'message': item['error']})
            if processed % 25 == 0:
                with self.connect() as db:
                    db.execute('UPDATE scans SET processed=? WHERE id=?', (processed, scan_id))

        try:
            for source in sources:
                try:
                    tracks, folders = self._collect(source, reset, progress)
                    if reset:
                        staged.append((source, tracks, folders))
                    else:
                        with self.lock, self.connect() as db:
                            self._apply(db, source, tracks, folders)
                except SourceRemoved:
                    continue
                except Exception as exc:
                    fatal = True
                    message = str(exc) if isinstance(exc, LibraryError) else 'Ошибка чтения папки; прежний каталог сохранён.'
                    if len(issues) < 100:
                        issues.append({'source_id': source['id'], 'message': message})
                    with self.connect() as db:
                        db.execute('UPDATE sources SET error=? WHERE id=?', (message, source['id']))
            if reset and not fatal:
                with self.lock, self.connect() as db:
                    for source, tracks, folders in staged:
                        self._apply(db, source, tracks, folders)
            status = 'failed' if reset and fatal else ('partial' if fatal or issues else 'completed')
        except Exception:
            status = 'failed'
            issues.append({'message': 'Внутренняя ошибка сканирования; повторите операцию.'})
        finally:
            with self.lock:
                try:
                    with self.connect() as db:
                        db.execute('UPDATE scans SET status=?,finished_at=?,processed=?,errors=? WHERE id=?', (status, now(), processed, json.dumps(issues, ensure_ascii=False), scan_id))
                finally:
                    self.job = None

    def catalog(self, query='', source_id=None, folder=None, offset=0, limit=50):
        conditions = ['t.available=1', 's.active=1']
        args = []
        if source_id:
            conditions.append('s.id=?')
            args.append(source_id)
        if folder is not None:
            conditions.append('t.folder=?')
            args.append(folder)
        if query:
            conditions.append("instr(casefold(t.title || ' ' || t.artist || ' ' || t.album || ' ' || t.path || ' ' || s.name), ?) > 0")
            args.append(query.casefold())
        clause = ' FROM tracks t JOIN sources s ON s.id=t.source_id WHERE ' + ' AND '.join(conditions)
        with self.connect() as db:
            count = db.execute('SELECT COUNT(*)' + clause, args).fetchone()[0]
            rows = db.execute('SELECT t.*,s.name AS source_name' + clause + ' ORDER BY casefold(t.path), t.id LIMIT ? OFFSET ?', args + [limit, offset]).fetchall()
            folders = db.execute('''SELECT f.source_id, f.path AS folder, s.name AS source_name
                FROM folders f JOIN sources s ON s.id=f.source_id
                WHERE s.active=1 ORDER BY s.name, f.path''').fetchall()
        return {'total': count, 'items': [dict(r) for r in rows], 'folders': [dict(r) for r in folders]}
