"""Client-only ASGI application. Administrative routes are never mounted here."""
import hashlib
import os
import secrets
import threading
import time
from collections import deque
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response

from .covers import Covers
from .library import Library, now
from .media import AudioResponse, open_track

COOKIE = 'detox_client'
SESSION_SECONDS = 30 * 24 * 60 * 60
TRACK_FIELDS = ('id', 'source_id', 'source_name', 'path', 'folder', 'filename',
                'title', 'artist', 'album', 'duration', 'size', 'error')


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


class Attempts:
    """Bounded process-local limiter. Proxy headers are not trusted by default."""
    def __init__(self):
        self.failures = deque(maxlen=300)
        self.lock = threading.Lock()

    def check(self, peer):
        with self.lock:
            current = time.monotonic()
            while self.failures and self.failures[0][0] < current - 60:
                self.failures.popleft()
            if len(self.failures) >= 300 or sum(p == peer for _, p in self.failures) >= 20:
                raise HTTPException(429, 'Слишком много попыток. Подождите минуту.', headers={'Retry-After': '60'})

    def failed(self, peer):
        with self.lock:
            self.failures.append((time.monotonic(), peer))


def create_app(data_dir=None, roots=None):
    data = Path(data_dir or os.getenv('DATA_DIR', '/data'))
    allowed = roots or [Path(p) for p in os.getenv('SOURCE_ROOTS', '/sources/music').split(';') if p]
    library = Library(data, allowed, recover_scans=False)
    covers = Covers(data)
    attempts = Attempts()
    app = FastAPI(title='DetoxPlayer API', docs_url=None, redoc_url=None, openapi_url=None)
    app.state.library = library

    @app.middleware('http')
    async def security_headers(request, call_next):
        response = await call_next(request)
        response.headers['Cache-Control'] = 'private, no-store'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Referrer-Policy'] = 'no-referrer'
        response.headers['X-Frame-Options'] = 'DENY'
        response.headers['Cross-Origin-Resource-Policy'] = 'same-origin'
        return response

    def csrf(request: Request):
        expected = f'{request.url.scheme}://{request.headers.get("host", "")}'
        if (request.headers.get('X-Detox-Client') != '1'
                or request.headers.get('origin') not in (None, expected)
                or request.headers.get('sec-fetch-site') == 'cross-site'):
            raise HTTPException(403, 'Недопустимый источник запроса.')

    def authorize(request: Request, bearer_only=False):
        peer = request.client.host if request.client else 'unknown'
        attempts.check(peer)
        authorization = request.headers.get('authorization')
        key = None
        with library.connect() as db:
            if authorization is not None:
                scheme, _, token = authorization.partition(' ')
                if scheme.lower() == 'bearer' and 1 <= len(token) <= 256:
                    key = db.execute('SELECT id,name FROM access_keys WHERE digest=? AND revoked_at IS NULL',
                                     (digest(token),)).fetchone()
            elif not bearer_only:
                session = request.cookies.get(COOKIE, '')
                if 1 <= len(session) <= 256:
                    key = db.execute('''SELECT k.id,k.name FROM client_sessions s JOIN access_keys k ON k.id=s.key_id
                        WHERE s.digest=? AND s.expires_at>? AND k.revoked_at IS NULL''',
                                     (digest(session), time.time())).fetchone()
            if key:
                db.execute('''INSERT INTO key_usage(key_id,last_used_at) VALUES(?,?)
                    ON CONFLICT(key_id) DO UPDATE SET last_used_at=excluded.last_used_at''', (key['id'], now()))
                return dict(key)
        attempts.failed(peer)
        raise HTTPException(401, 'Ключ недействителен или отозван.', headers={'WWW-Authenticate': 'Bearer'})

    def authorized(request: Request):
        return authorize(request)

    @app.get('/health')
    def health():
        return {'status': 'ok'}

    @app.get('/api/v1/me')
    def me(key=Depends(authorized)):
        return {'device': key, 'api_version': 1}

    @app.post('/api/v1/session', dependencies=[Depends(csrf)])
    def session(request: Request, response: Response):
        key = authorize(request, bearer_only=True)
        token = secrets.token_urlsafe(32)
        expires = time.time() + SESSION_SECONDS
        with library.connect() as db:
            db.execute('DELETE FROM client_sessions WHERE expires_at<=?', (time.time(),))
            # Re-check inside the write transaction so concurrent revocation wins.
            created = db.execute('''INSERT INTO client_sessions(digest,key_id,expires_at)
                SELECT ?,id,? FROM access_keys WHERE id=? AND revoked_at IS NULL''', (digest(token), expires, key['id']))
            if not created.rowcount:
                raise HTTPException(401, 'Ключ недействителен или отозван.')
            # At most 10 browser sessions per key, oldest first.
            db.execute('''DELETE FROM client_sessions WHERE key_id=? AND digest NOT IN
                (SELECT digest FROM client_sessions WHERE key_id=? ORDER BY expires_at DESC LIMIT 10)''', (key['id'], key['id']))
        response.set_cookie(COOKIE, token, httponly=True, samesite='strict',
                            secure=request.url.scheme == 'https', max_age=SESSION_SECONDS, path='/api/v1')
        return {'device': key, 'expires_at': expires}

    @app.delete('/api/v1/session', dependencies=[Depends(csrf)])
    def logout(request: Request, response: Response):
        # Idempotent even after expiry/revocation; never requires the original key.
        with library.connect() as db:
            db.execute('DELETE FROM client_sessions WHERE digest=?', (digest(request.cookies.get(COOKIE, '')),))
        response.delete_cookie(COOKIE, path='/api/v1')
        return {'ok': True}

    def public_track(track):
        return {field: track[field] for field in TRACK_FIELDS} | {
            'audio_url': f'/api/v1/tracks/{track["id"]}/audio',
            'cover_url': f'/api/v1/tracks/{track["id"]}/cover',
        }

    @app.get('/api/v1/sources', dependencies=[Depends(authorized)])
    def sources():
        return {'items': [{key: s[key] for key in ('id', 'name', 'tracks', 'available')} for s in library.sources()]}

    @app.get('/api/v1/tracks', dependencies=[Depends(authorized)])
    def tracks(q: str = Query('', max_length=300), source_id: str | None = None, folder: str | None = None,
               offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=200)):
        result = library.catalog(q, source_id, folder, offset, limit)
        return {'total': result['total'], 'offset': offset, 'limit': limit,
                'items': [public_track(t) for t in result['items']]}

    @app.get('/api/v1/folders', dependencies=[Depends(authorized)])
    def folders(source_id: str | None = None, offset: int = Query(0, ge=0), limit: int = Query(100, ge=1, le=500)):
        with library.connect() as db:
            clause = ' FROM folders f JOIN sources s ON s.id=f.source_id WHERE s.active=1'
            args = []
            if source_id:
                clause += ' AND f.source_id=?'
                args.append(source_id)
            total = db.execute('SELECT COUNT(*)' + clause, args).fetchone()[0]
            rows = db.execute('SELECT f.source_id,f.path AS folder,s.name AS source_name' + clause +
                              ' ORDER BY s.name,f.path LIMIT ? OFFSET ?', args + [limit, offset]).fetchall()
        return {'total': total, 'offset': offset, 'limit': limit, 'items': [dict(r) for r in rows]}

    @app.get('/api/v1/tracks/{track_id}', dependencies=[Depends(authorized)])
    def track(track_id: str):
        row, _, _, handle = open_track(library, track_id)
        handle.close()
        return public_track(row)

    @app.api_route('/api/v1/tracks/{track_id}/audio', methods=['GET', 'HEAD'], dependencies=[Depends(authorized)])
    def audio(track_id: str, request: Request, download: bool = False):
        row, _, _, handle = open_track(library, track_id)
        return AudioResponse(handle, request, row['filename'], download)

    @app.api_route('/api/v1/tracks/{track_id}/cover', methods=['GET', 'HEAD'], dependencies=[Depends(authorized)])
    def cover(track_id: str, request: Request):
        _, root, path, handle = open_track(library, track_id)
        with handle:
            with library.connect() as db:
                reset = db.execute("""SELECT id FROM scans WHERE mode='reset'
                    AND status IN ('completed','partial') ORDER BY rowid DESC LIMIT 1""").fetchone()
            # Successful index replacement starts a fresh derived cache namespace.
            # Old entries remain bounded by eviction; failed resets keep the cache.
            result = covers.get(track_id, root, path, handle, reset['id'] if reset else None)
        return Response(content=result if request.method == 'GET' else b'', media_type='image/jpeg',
                        headers={'Content-Length': str(len(result))})

    return app
