"""Read-only media delivery. Never accepts a client-supplied filesystem path."""
import hashlib
import os
import re
import stat
from email.utils import formatdate
from urllib.parse import quote

import anyio
from fastapi import HTTPException
from starlette.responses import StreamingResponse


def open_track(library, track_id):
    with library.connect() as db:
        row = db.execute('''SELECT t.*,s.path AS source_path,s.name AS source_name
            FROM tracks t JOIN sources s ON s.id=t.source_id
            WHERE t.id=? AND t.available=1 AND s.active=1''', (track_id,)).fetchone()
    if row is None:
        raise HTTPException(404, 'Трек недоступен.')
    handle = None
    try:
        root = library.allowed(row['source_path'])
        path = (root / row['path']).resolve(strict=True)
        if root not in path.parents or path.suffix.lower() != '.mp3':
            raise ValueError('Outside source')
        library.allowed(str(path))
        # NOFOLLOW rejects a last-moment replacement of the resolved file by a symlink.
        fd = os.open(path, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0) | getattr(os, 'O_NONBLOCK', 0))
        handle = os.fdopen(fd, 'rb')
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            raise ValueError('Not a regular file')
        return dict(row), root, path, handle
    except Exception:
        if handle:
            handle.close()
        raise HTTPException(404, 'Трек недоступен.') from None


def byte_range(value, size):
    """One byte range is sufficient for seeking and resumable downloads.

    Unknown units and multipart requests are ignored (a full 200 response).
    Malformed or unsatisfiable single-byte requests receive 416.
    """
    if not value or not value.startswith('bytes=') or ',' in value:
        return None
    match = re.fullmatch(r'bytes=(\d*)-(\d*)', value)
    if not match or not any(match.groups()) or len(value) > 100:
        raise HTTPException(416, 'Недопустимый диапазон.', headers={'Content-Range': f'bytes */{size}'})
    first, last = match.groups()
    start = int(first) if first else max(0, size - int(last))
    end = min(int(last), size - 1) if first and last else size - 1
    if size == 0 or start >= size or start > end:
        raise HTTPException(416, 'Недопустимый диапазон.', headers={'Content-Range': f'bytes */{size}'})
    return start, end


class AudioResponse(StreamingResponse):
    """Own the opened descriptor, including HEAD, disconnect and failed sends."""
    def __init__(self, handle, request, filename, download=False):
        self.handle = handle
        try:
            info = os.fstat(handle.fileno())
            size = info.st_size
            etag = '"' + hashlib.sha256(f'{info.st_ino}:{size}:{info.st_mtime_ns}'.encode()).hexdigest() + '"'
            modified = formatdate(info.st_mtime, usegmt=True)
            headers = {'Accept-Ranges': 'bytes', 'ETag': etag, 'Last-Modified': modified,
                       'Content-Disposition': f'{"attachment" if download else "inline"}; filename*=UTF-8\'\'{quote(filename, safe="")}' }
            requested = request.headers.get('range') if request.method == 'GET' else None
            if request.headers.get('if-range') not in (None, etag, modified):
                requested = None
            selected = byte_range(requested, size)
            start, end = selected if selected else (0, size - 1)
            length = max(0, end - start + 1)
            headers['Content-Length'] = str(length)
            if selected:
                headers['Content-Range'] = f'bytes {start}-{end}/{size}'

            async def chunks():
                if request.method == 'HEAD':
                    return
                await anyio.to_thread.run_sync(handle.seek, start)
                remaining = length
                while remaining:
                    block = await anyio.to_thread.run_sync(handle.read, min(65536, remaining))
                    if not block:
                        break
                    remaining -= len(block)
                    yield block

            super().__init__(chunks(), status_code=206 if selected else 200,
                             media_type='audio/mpeg', headers=headers)
        except BaseException:
            handle.close()
            raise

    async def __call__(self, scope, receive, send):
        try:
            await super().__call__(scope, receive, send)
        finally:
            self.handle.close()
