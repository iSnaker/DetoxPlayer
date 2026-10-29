import sys
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).parents[1]))
from app.main import create_app


@pytest.fixture
def environment(tmp_path):
    root = tmp_path / 'music'
    root.mkdir()
    data = tmp_path / 'data'
    app = create_app(data, [root])
    with TestClient(app, base_url='http://localhost') as client:
        yield client, app.state.library, root, data


def login(client, data):
    secret = (data / 'admin-secret').read_text()
    assert client.post('/admin/login', json={'secret': secret}, headers={'X-Detox-Admin': '1'}).status_code == 200
    client.headers.update({'X-Detox-Admin': '1'})


def wait_for_scan(library):
    deadline = time.monotonic() + 10
    while library.job and time.monotonic() < deadline:
        time.sleep(0.01)
    assert not library.job, 'Scan did not finish'
    return library.latest_scan()
