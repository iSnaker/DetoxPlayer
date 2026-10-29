import hashlib

from conftest import login


def test_admin_requires_login_and_csrf(environment):
    client, lib, root, data = environment
    assert client.get('/admin/state').status_code == 401
    secret = (data/'admin-secret').read_text()
    assert client.post('/admin/login', json={'secret':secret}).status_code == 403
    assert client.post('/admin/login', json={'secret':secret}, headers={'X-Detox-Admin':'1','Origin':'https://evil.example'}).status_code == 403
    login(client, data)
    assert client.get('/admin/state').status_code == 200
    assert client.get('/admin/state', headers={'Host':'evil.example'}).status_code == 403
    assert client.post('/admin/scans', json={}, headers={'Origin':'https://evil.example'}).status_code == 403
    assert client.post('/admin/logout').status_code == 200
    assert client.get('/admin/state').status_code == 401


def test_login_rate_limit(environment):
    client, lib, root, data = environment
    for _ in range(10):
        assert client.post('/admin/login', json={'secret':'bad'}, headers={'X-Detox-Admin':'1'}).status_code == 401
    assert client.post('/admin/login', json={'secret':'bad'}, headers={'X-Detox-Admin':'1'}).status_code == 429


def test_key_secret_only_returned_once_and_revoke(environment):
    client, lib, root, data = environment
    login(client, data)
    response = client.post('/admin/keys', json={'name':'iPhone'})
    assert response.status_code == 201
    result = response.json()
    assert result['key'].startswith('dtp_')
    listed = client.get('/admin/keys').json()
    assert 'key' not in listed[0] and 'digest' not in listed[0]
    with lib.connect() as db:
        stored = dict(db.execute('SELECT * FROM access_keys').fetchone())
    assert stored['digest'] == hashlib.sha256(result['key'].encode()).hexdigest()
    assert stored['digest'] != result['key']
    assert client.delete('/admin/keys/'+result['id']).status_code == 200
    assert client.get('/admin/keys').json()[0]['revoked_at']


def test_security_headers_and_cookie(environment):
    client, lib, root, data = environment
    login(client, data)
    assert client.cookies.get('detox_admin')
    response = client.get('/')
    assert response.status_code == 200
    assert response.headers['X-Frame-Options'] == 'DENY'
    assert "script-src 'self'" in response.headers['Content-Security-Policy']
    assert response.headers['Cache-Control'] == 'no-store'
    assert client.get('/static/app.js').status_code == 200
