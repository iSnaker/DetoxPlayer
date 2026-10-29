import hashlib
import hmac
import os
import secrets
import threading
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .library import Library, LibraryError, now

STATIC = Path(__file__).parent / 'static'
COOKIE = 'detox_admin'


class Login(BaseModel):
    secret: str = Field(min_length=1, max_length=256)


class SourceInput(BaseModel):
    name: str = Field(default='', max_length=150)
    path: str = Field(min_length=1, max_length=4096)


class ScanInput(BaseModel):
    source_id: str | None = None
    reset: bool = False


class KeyInput(BaseModel):
    name: str = Field(min_length=1, max_length=150)


def create_app(data_dir=None, roots=None):
    data = Path(data_dir or os.getenv('DATA_DIR', '/data'))
    allowed_roots = roots or [Path(p) for p in os.getenv('SOURCE_ROOTS', '/sources/music').split(';') if p]
    library = Library(data, allowed_roots)
    secret_path = data / 'admin-secret'
    if not secret_path.exists():
        try:
            with secret_path.open('x') as file:
                file.write(secrets.token_urlsafe(32))
            secret_path.chmod(0o600)
        except FileExistsError:
            pass
    admin_secret = secret_path.read_text().strip()
    sessions = {}
    session_lock = threading.Lock()
    failures = []

    @asynccontextmanager
    async def lifespan(app):
        yield
        # Wait for scan completion before process shutdown; SQLite commits remain atomic.
        while library.job:
            import asyncio
            await asyncio.sleep(0.05)

    app = FastAPI(title='DetoxPlayer Admin', lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)
    app.state.library = library

    @app.exception_handler(LibraryError)
    async def library_error(request, exc):
        from fastapi.responses import JSONResponse
        return JSONResponse(status_code=409, content={'detail': str(exc)})

    @app.middleware('http')
    async def security_headers(request, call_next):
        response = await call_next(request)
        response.headers['Cache-Control'] = 'no-store'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['X-Frame-Options'] = 'DENY'
        response.headers['Content-Security-Policy'] = "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'self'"
        response.headers['Referrer-Policy'] = 'no-referrer'
        return response

    def local_request(request: Request):
        # Do not trust forwarded host headers or the peer IP of a Docker NAT gateway.
        host = request.url.hostname
        if host not in {'localhost', '127.0.0.1', '[::1]', '::1'}:
            raise HTTPException(403, 'Панель доступна только через localhost.')
        if request.method not in ('GET', 'HEAD'):
            if request.headers.get('X-Detox-Admin') != '1':
                raise HTTPException(403, 'Отсутствует защита запроса.')
            origin = request.headers.get('origin')
            expected = f'{request.url.scheme}://{request.headers.get("host", "")}'
            if origin and origin != expected:
                raise HTTPException(403, 'Недопустимый источник запроса.')

    def admin(request: Request):
        local_request(request)
        session = request.cookies.get(COOKIE, '')
        with session_lock:
            expiry = sessions.get(session, 0)
        if expiry < time.time():
            raise HTTPException(401, 'Войдите в локальную панель.')

    @app.get('/health')
    def health():
        return {'status': 'ok'}

    @app.get('/')
    def index(request: Request):
        local_request(request)
        return FileResponse(STATIC / 'index.html')

    @app.post('/admin/login')
    def login(payload: Login, request: Request, response: Response):
        local_request(request)
        current = time.time()
        with session_lock:
            failures[:] = [stamp for stamp in failures if stamp > current - 60]
            if len(failures) >= 10:
                raise HTTPException(429, 'Слишком много попыток. Подождите минуту.')
            if not hmac.compare_digest(payload.secret.encode(), admin_secret.encode()):
                failures.append(current)
                raise HTTPException(401, 'Неверный административный секрет.')
            for key, expiry in list(sessions.items()):
                if expiry < current:
                    del sessions[key]
            session = secrets.token_urlsafe(32)
            sessions[session] = current + 12 * 60 * 60
        response.set_cookie(COOKIE, session, httponly=True, samesite='strict', secure=request.url.scheme == 'https', max_age=12 * 60 * 60)
        return {'ok': True}

    @app.post('/admin/logout', dependencies=[Depends(admin)])
    def logout(request: Request, response: Response):
        with session_lock:
            sessions.pop(request.cookies.get(COOKIE), None)
        response.delete_cookie(COOKIE)
        return {'ok': True}

    @app.get('/admin/state', dependencies=[Depends(admin)])
    def state():
        return {'sources': library.sources(), 'scan': library.latest_scan()}

    @app.get('/admin/browse', dependencies=[Depends(admin)])
    def browse(path: str | None = None):
        return library.browse(path)

    @app.post('/admin/sources', dependencies=[Depends(admin)], status_code=201)
    def add_source(payload: SourceInput):
        # Mutations are serialized so another request cannot start a scan between add and scan.
        with library.lock:
            source_id = library.add_source(payload.name, payload.path)
            scan_id = library.start_scan(source_id)
        return {'id': source_id, 'scan_id': scan_id}

    @app.delete('/admin/sources/{source_id}', dependencies=[Depends(admin)])
    def remove_source(source_id: str):
        library.remove_source(source_id)
        return {'ok': True}

    @app.post('/admin/scans', dependencies=[Depends(admin)], status_code=202)
    def scan(payload: ScanInput):
        return {'id': library.start_scan(payload.source_id, payload.reset)}

    @app.get('/admin/tracks', dependencies=[Depends(admin)])
    def tracks(q: str = Query('', max_length=300), source_id: str | None = None, folder: str | None = None,
               offset: int = Query(0, ge=0), limit: int = Query(50, ge=1, le=200)):
        return library.catalog(q, source_id, folder, offset, limit)

    @app.get('/admin/keys', dependencies=[Depends(admin)])
    def keys():
        with library.connect() as db:
            return [dict(r) for r in db.execute('SELECT id,name,created_at,revoked_at FROM access_keys ORDER BY created_at DESC')]

    @app.post('/admin/keys', dependencies=[Depends(admin)], status_code=201)
    def create_key(payload: KeyInput):
        if not payload.name.strip():
            raise HTTPException(422, 'Укажите название устройства.')
        key_id, token = uuid.uuid4().hex, 'dtp_' + secrets.token_urlsafe(32)
        with library.connect() as db:
            db.execute('INSERT INTO access_keys(id,name,digest,created_at) VALUES(?,?,?,?)', (key_id, payload.name.strip(), hashlib.sha256(token.encode()).hexdigest(), now()))
        return {'id': key_id, 'key': token}

    @app.delete('/admin/keys/{key_id}', dependencies=[Depends(admin)])
    def revoke_key(key_id: str):
        with library.connect() as db:
            row = db.execute('UPDATE access_keys SET revoked_at=COALESCE(revoked_at,?) WHERE id=?', (now(), key_id))
            if not row.rowcount:
                raise HTTPException(404, 'Ключ не найден.')
        return {'ok': True}

    app.mount('/static', StaticFiles(directory=STATIC), name='static')
    return app
