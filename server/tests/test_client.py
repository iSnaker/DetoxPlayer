import asyncio
import hashlib
import io
import os
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from mutagen.id3 import ID3, APIC
from PIL import Image
from starlette.requests import Request
from starlette.requests import ClientDisconnect

from app.client import COOKIE, create_app
from app.media import AudioResponse
from conftest import login, wait_for_scan


def picture(color):
    out = io.BytesIO()
    Image.new('RGB', (24, 24), color).save(out, format='PNG')
    return out.getvalue()


@pytest.fixture
def playback(environment):
    admin, library, root, data = environment
    login(admin, data)
    folder = root / 'Альбом'
    folder.mkdir()
    audio = folder / '01 Песня.mp3'
    content = bytes(range(256)) * 64
    audio.write_bytes(content)
    source = admin.post('/admin/sources', json={'name': 'Музыка', 'path': str(root)}).json()['id']
    wait_for_scan(library)
    track = library.catalog()['items'][0]['id']
    issued = admin.post('/admin/keys', json={'name': 'Phone'}).json()
    with TestClient(create_app(data, [root]), base_url='http://localhost') as api:
        yield api, admin, library, root, data, audio, content, source, track, issued


def bearer(issued):
    return {'Authorization': 'Bearer ' + issued['key']}


def test_client_catalog_and_admin_separation(playback):
    api, admin, lib, root, data, audio, content, source, track, key = playback
    headers = bearer(key)
    for path in ('/api/v1/me', '/api/v1/sources', '/api/v1/folders', '/api/v1/tracks',
                 f'/api/v1/tracks/{track}', f'/api/v1/tracks/{track}/audio', f'/api/v1/tracks/{track}/cover'):
        assert api.get(path).status_code == 401
        result = api.get(path, headers=headers)
        assert result.status_code == 200
        if result.headers['content-type'].startswith('application/json'):
            assert str(root) not in result.text
            assert 'source_path' not in result.text
    assert api.get('/admin/state', headers=headers).status_code == 404
    assert api.post('/admin/keys', headers=headers, json={'name': 'bad'}).status_code == 404
    api.cookies.set('detox_admin', admin.cookies.get('detox_admin'))
    assert api.get('/api/v1/tracks').status_code == 401
    assert admin.get('/api/v1/tracks', headers=headers).status_code == 404
    result = api.get('/api/v1/tracks', params={'q': 'ПЕСНЯ'}, headers=headers).json()
    assert result['total'] == 1
    assert result['items'][0]['audio_url'].endswith(f'/{track}/audio')
    assert api.get('/api/v1/tracks', params={'offset': 1}, headers=headers).json()['items'] == []
    assert api.get('/api/v1/tracks?limit=201', headers=headers).status_code == 422
    assert api.get('/api/v1/folders', params={'source_id': source, 'limit': 1}, headers=headers).json()['total'] == 2
    assert admin.get('/admin/keys').json()[0]['last_used_at']
    assert api.get('/api/v1/tracks', params={'key': key['key']}).status_code == 401


def test_library_export_and_version(playback):
    api, admin, lib, root, data, audio, content, source, track, key = playback
    headers = bearer(key)
    for path in ('/api/v1/library/version', '/api/v1/library/export'):
        assert api.get(path).status_code == 401
    version = api.get('/api/v1/library/version', headers=headers).json()
    assert version['total'] == 1
    plain = api.get('/api/v1/library/export', headers=headers | {'Accept-Encoding': 'identity'})
    assert 'content-encoding' not in plain.headers
    assert plain.json()['version'] == version['version']
    assert plain.json()['items'][0]['id'] == track
    assert str(root) not in plain.text
    zipped = api.get('/api/v1/library/export', headers=headers | {'Accept-Encoding': 'gzip'})
    assert zipped.headers['content-encoding'] == 'gzip'
    assert zipped.json() == plain.json()
    (root / 'Альбом' / '02 Новая.mp3').write_bytes(content)
    lib.start_scan(None)
    wait_for_scan(lib)
    changed = api.get('/api/v1/library/version', headers=headers).json()
    assert changed['total'] == 2 and changed['version'] != version['version']


@pytest.mark.parametrize('requested,start,end', [('bytes=0-99', 0, 99), ('bytes=100-', 100, 16383),
                                                ('bytes=-100', 16284, 16383), ('bytes=16380-99999', 16380, 16383)])
def test_ranges(playback, requested, start, end):
    api, _, _, _, _, _, content, _, track, key = playback
    result = api.get(f'/api/v1/tracks/{track}/audio', headers=bearer(key) | {'Range': requested})
    assert result.status_code == 206
    assert result.content == content[start:end+1]
    assert int(result.headers['content-length']) == end-start+1
    assert result.headers['content-range'] == f'bytes {start}-{end}/{len(content)}'
    assert result.headers['accept-ranges'] == 'bytes'
    assert result.headers['content-type'] == 'audio/mpeg'


@pytest.mark.parametrize('requested', ['bytes=999999-', 'bytes=10-9', 'bytes=-0', 'bytes=-', 'bytes=bad', 'bytes='+'9'*101+'-'])
def test_unsatisfiable_ranges(playback, requested):
    api, _, _, _, _, _, content, _, track, key = playback
    result = api.get(f'/api/v1/tracks/{track}/audio', headers=bearer(key) | {'Range': requested})
    assert result.status_code == 416
    assert result.headers['content-range'] == f'bytes */{len(content)}'


def test_head_download_and_if_range(playback):
    api, _, _, _, _, _, content, _, track, key = playback
    url = f'/api/v1/tracks/{track}/audio'
    headers = bearer(key)
    head = api.head(url, headers=headers | {'Range': 'bytes=0-9'})
    assert head.status_code == 200
    assert head.content == b''
    assert int(head.headers['content-length']) == len(content)
    full = api.get(url, headers=headers)
    assert full.content == content
    assert full.headers['etag'] == head.headers['etag']
    assert full.headers['content-disposition'].startswith('inline;')
    assert api.get(url+'?download=true', headers=headers).headers['content-disposition'].startswith('attachment;')
    for validator in (head.headers['etag'], head.headers['last-modified']):
        assert api.get(url, headers=headers | {'Range': 'bytes=0-9', 'If-Range': validator}).content == content[:10]
    assert api.get(url, headers=headers | {'Range': 'bytes=0-9', 'If-Range': '"old"'}).content == content
    assert api.get(url, headers=headers | {'Range': 'bytes=0-1,5-6'}).status_code == 200
    assert api.head(url).status_code == 401


def test_revocation_blocks_bearer_session_and_cached_cover(playback):
    api, admin, _, _, _, _, _, _, track, key = playback
    headers = bearer(key)
    assert api.post('/api/v1/session', headers=headers | {'X-Detox-Client': '1'}).status_code == 200
    assert api.get(f'/api/v1/tracks/{track}/cover').status_code == 200
    assert admin.delete('/admin/keys/'+key['id']).status_code == 200
    for path in ('/api/v1/me', '/api/v1/tracks', f'/api/v1/tracks/{track}/cover', f'/api/v1/tracks/{track}/audio'):
        assert api.get(path).status_code == 401
        assert api.get(path, headers=headers | {'Range': 'bytes=0-9'}).status_code == 401


def test_session_cookie_csrf_expiry_and_restart(playback):
    api, _, lib, root, data, _, _, _, _, key = playback
    headers = bearer(key)
    url = '/api/v1/session'
    assert api.post(url, headers=headers).status_code == 403
    assert api.post(url, headers=headers | {'X-Detox-Client': '1', 'Origin': 'https://evil.invalid'}).status_code == 403
    result = api.post(url, headers=headers | {'X-Detox-Client': '1', 'Origin': 'http://localhost'})
    assert result.status_code == 200
    cookie = result.headers['set-cookie']
    assert 'HttpOnly' in cookie and 'SameSite=strict' in cookie and 'Path=/api/v1' in cookie
    token = api.cookies.get(COOKIE)
    assert token not in result.text
    with lib.connect() as db:
        stored = db.execute('SELECT digest FROM client_sessions').fetchone()[0]
        assert stored == hashlib.sha256(token.encode()).hexdigest()
    assert api.get('/api/v1/me').status_code == 200
    assert api.get('/api/v1/me', headers={'Authorization':'Bearer wrong'}).status_code == 401
    with TestClient(create_app(data, [root]), base_url='http://localhost') as restarted:
        restarted.cookies.set(COOKIE, token, path='/api/v1')
        assert restarted.get('/api/v1/me').status_code == 200
    assert api.delete(url).status_code == 403
    assert api.delete(url, headers={'X-Detox-Client':'1'}).status_code == 200
    assert api.get('/api/v1/me').status_code == 401
    api.post(url, headers=headers | {'X-Detox-Client': '1'})
    with lib.connect() as db:
        db.execute('UPDATE client_sessions SET expires_at=?', (time.time()-1,))
    assert api.get('/api/v1/me').status_code == 401
    with TestClient(create_app(data, [root]), base_url='https://localhost') as https:
        response = https.post(url, headers=headers | {'X-Detox-Client':'1'})
        assert '; Secure' in response.headers['set-cookie']


def test_bad_keys_are_rate_limited(playback):
    api = playback[0]
    for _ in range(20):
        assert api.get('/api/v1/me', headers={'Authorization':'Bearer bad'}).status_code == 401
    result = api.get('/api/v1/me', headers={'Authorization':'Bearer bad'})
    assert result.status_code == 429 and result.headers['retry-after'] == '60'


def test_revocation_during_session_creation(playback, monkeypatch):
    api, admin, lib, _, _, _, _, _, _, key = playback
    def revoke_before_insert(_):
        assert admin.delete('/admin/keys/'+key['id']).status_code == 200
        return 'test-session'
    monkeypatch.setattr('app.client.secrets.token_urlsafe', revoke_before_insert)
    response = api.post('/api/v1/session', headers=bearer(key) | {'X-Detox-Client':'1'})
    assert response.status_code == 401
    assert 'set-cookie' not in response.headers
    with lib.connect() as db:
        assert db.execute('SELECT COUNT(*) FROM client_sessions').fetchone()[0] == 0


def test_session_count_is_bounded(playback):
    api, _, lib, *_rest, key = playback
    for _ in range(12):
        assert api.post('/api/v1/session', headers=bearer(key) | {'X-Detox-Client':'1'}).status_code == 200
    with lib.connect() as db:
        assert db.execute('SELECT COUNT(*) FROM client_sessions').fetchone()[0] == 10


def test_offline_source_keeps_catalog_but_cannot_serve(playback):
    api, _, _, root, _, _, _, _, track, key = playback
    root.rename(root.with_name('offline'))
    headers = bearer(key)
    assert api.get('/api/v1/tracks', headers=headers).json()['total'] == 1
    assert api.get('/api/v1/sources', headers=headers).json()['items'][0]['available'] is False
    assert api.get(f'/api/v1/tracks/{track}/audio', headers=headers).status_code == 404


def test_source_removal_missing_file_and_traversal(playback):
    api, admin, lib, root, data, audio, content, source, track, key = playback
    headers = bearer(key)
    url = f'/api/v1/tracks/{track}/audio'
    outside = root.parent / 'private.mp3'
    outside.write_bytes(b'private')
    with lib.connect() as db:
        original = db.execute('SELECT path FROM tracks WHERE id=?', (track,)).fetchone()[0]
        db.execute('UPDATE tracks SET path=? WHERE id=?', ('../private.mp3', track))
    assert api.get(url, headers=headers).status_code == 404
    with lib.connect() as db:
        db.execute('UPDATE tracks SET path=? WHERE id=?', (original, track))
    audio.unlink()
    assert api.get(url, headers=headers).status_code == 404
    audio.symlink_to(outside)
    assert api.get(url, headers=headers).status_code == 404
    assert api.get(f'/api/v1/tracks/{track}/cover', headers=headers).status_code == 404
    audio.unlink()
    audio.write_bytes(content)
    assert admin.delete('/admin/sources/'+source).status_code == 200
    assert api.get(url, headers=headers).status_code == 404
    assert api.get('/api/v1/tracks', headers=headers).json()['total'] == 0
    assert audio.read_bytes() == content


def test_starting_api_does_not_interrupt_scan(playback):
    _, _, lib, root, data, *_ = playback
    with lib.connect() as db:
        db.execute("INSERT INTO scans(id,mode,status,started_at) VALUES('live','rescan','running','now')")
    create_app(data, [root])
    with lib.connect() as db:
        assert db.execute("SELECT status FROM scans WHERE id='live'").fetchone()[0] == 'running'


def test_covers_precedence_cache_refresh_and_safe_fallback(playback):
    api, _, _, root, data, audio, _, _, track, key = playback
    url = f'/api/v1/tracks/{track}/cover'
    headers = bearer(key)
    empty = api.get(url, headers=headers)
    assert empty.status_code == 200 and empty.headers['content-type'] == 'image/jpeg'
    assert Image.open(io.BytesIO(empty.content)).size == (256, 256)
    folder = audio.parent / 'folder.jpg'
    cover = audio.parent / 'cover.jpg'
    folder.write_bytes(picture('blue'))
    assert Image.open(io.BytesIO(api.get(url, headers=headers).content)).getpixel((0, 0))[2] > 200
    cover.write_bytes(picture('red'))
    assert Image.open(io.BytesIO(api.get(url, headers=headers).content)).getpixel((0, 0))[0] > 200
    tags = ID3()
    tags.add(APIC(encoding=3, mime='image/png', type=3, data=picture('green')))
    tags.save(audio)
    original = audio.read_bytes()
    embedded = api.get(url, headers=headers)
    assert Image.open(io.BytesIO(embedded.content)).getpixel((0, 0))[1] > 100
    assert api.head(url, headers=headers).content == b''
    assert int(api.head(url, headers=headers).headers['content-length']) == len(embedded.content)
    assert audio.read_bytes() == original
    assert api.get(url, headers=headers).content == embedded.content
    # Corrupt embedded data falls through to sidecar; a symlink outside source is ignored.
    tags = ID3()
    tags.add(APIC(encoding=3, mime='image/png', type=3, data=b'bad'))
    tags.save(audio)
    cover.unlink()
    outside = root.parent / 'outside.jpg'
    outside.write_bytes(picture('red'))
    cover.symlink_to(outside)
    assert Image.open(io.BytesIO(api.get(url, headers=headers).content)).getpixel((0, 0))[2] > 200
    folder.write_bytes(b'not an image')
    assert api.get(url, headers=headers).content == empty.content


def test_audio_descriptor_closed_when_client_disconnects(tmp_path):
    file = tmp_path / 'audio.mp3'
    file.write_bytes(b'x' * 200000)
    handle = file.open('rb')
    scope = {'type': 'http', 'method': 'GET', 'headers': [], 'asgi': {'version':'3.0', 'spec_version':'2.4'}}
    response = AudioResponse(handle, Request(scope), 'audio.mp3')
    sent = []
    async def receive():
        await asyncio.sleep(10)
    async def send(message):
        sent.append(message)
        if message['type'] == 'http.response.body':
            raise OSError('client disconnected')
    with pytest.raises(ClientDisconnect):
        asyncio.run(response(scope, receive, send))
    assert handle.closed
    assert len([m for m in sent if m['type'] == 'http.response.body']) == 1


def test_full_reset_rebuilds_derived_cover(playback):
    api, _, lib, _, data, _, _, source, track, key = playback
    url = f'/api/v1/tracks/{track}/cover'
    original = api.get(url, headers=bearer(key)).content
    cached = next((data / 'covers').glob('*.jpg'))
    cached.write_bytes(b'obsolete cached representation')
    lib.start_scan(source, reset=True)
    wait_for_scan(lib)
    assert api.get(url, headers=bearer(key)).content == original
