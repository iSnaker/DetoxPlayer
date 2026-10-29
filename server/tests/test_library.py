import threading
from pathlib import Path

import pytest
from mutagen.id3 import ID3, TALB, TIT2, TPE1

from app.library import Library, LibraryError, readable_tag
from conftest import login, wait_for_scan


def add(client, library, path, name='Моя музыка'):
    response = client.post('/admin/sources', json={'name': name, 'path': str(path)})
    assert response.status_code == 201, response.text
    wait_for_scan(library)
    return response.json()['id']


def test_source_lifecycle_and_missing_tags(environment):
    client, lib, root, data = environment
    login(client, data)
    (root / '01.mp3').write_bytes(b'invalid mp3')
    source = add(client, lib, root)
    tracks = client.get('/admin/tracks').json()
    assert tracks['total'] == 1
    track = tracks['items'][0]
    assert track['title'] == '01'
    assert track['artist'] == 'Неизвестный исполнитель'
    assert track['error']
    assert lib.latest_scan()['status'] == 'partial'
    assert client.get('/admin/tracks?q=01').json()['total'] == 1
    assert client.delete(f'/admin/sources/{source}').status_code == 200
    assert client.get('/admin/tracks').json()['total'] == 0
    assert (root / '01.mp3').exists()


def test_rescan_add_delete_and_stable_ids(environment):
    client, lib, root, data = environment
    login(client, data)
    (root / 'one.mp3').write_bytes(b'one')
    source = add(client, lib, root)
    original = lib.catalog()['items'][0]['id']
    (root / 'two.mp3').write_bytes(b'two')
    lib.start_scan(source)
    wait_for_scan(lib)
    rows = lib.catalog()['items']
    assert len(rows) == 2
    assert next(t for t in rows if t['filename'] == 'one.mp3')['id'] == original
    (root / 'two.mp3').unlink()
    lib.start_scan(source)
    wait_for_scan(lib)
    assert lib.catalog()['total'] == 1
    assert lib.catalog()['items'][0]['id'] == original
    lib.start_scan(source, reset=True)
    wait_for_scan(lib)
    assert lib.catalog()['items'][0]['id'] == original


def test_cyrillic_tags_and_literal_search(environment, monkeypatch):
    client, lib, root, data = environment
    login(client, data)
    file = root / '01.mp3'
    file.write_bytes(b'audio')
    # Isolate metadata extraction from decoder requirements; feed real ID3 frames.
    tags = ID3()
    tags.add(TIT2(encoding=3, text='Песня Ёжика 100%'))
    tags.add(TPE1(encoding=3, text='Исполнитель'))
    tags.add(TALB(encoding=3, text='Альбом'))
    tags.save(file)
    from mutagen.easyid3 import EasyID3
    class Audio(dict):
        info = type('Info', (), {'length': 12.5})()
    monkeypatch.setattr('app.library.File', lambda path, easy: Audio(EasyID3(path)))
    add(client, lib, root)
    assert lib.catalog('ПЕСНЯ ЁЖИКА')['total'] == 1
    assert lib.catalog('ИСПОЛНИТЕЛЬ')['total'] == 1
    assert lib.catalog('%')['total'] == 1
    assert lib.catalog("' OR 1=1 --")['total'] == 0
    assert lib.catalog()['items'][0]['duration'] == 12.5


def test_source_isolation_overlap_and_escape(environment, tmp_path):
    client, lib, root, data = environment
    login(client, data)
    first, second = root/'A', root/'B'
    first.mkdir(); second.mkdir()
    (first/'01.mp3').write_bytes(b'a')
    (second/'01.mp3').write_bytes(b'b')
    a = add(client, lib, first, 'A')
    b = add(client, lib, second, 'B')
    assert lib.catalog()['total'] == 2
    assert lib.catalog(source_id=a)['total'] == 1
    assert lib.catalog(source_id=b)['total'] == 1
    for path in (root, first, tmp_path):
        response = client.post('/admin/sources', json={'path': str(path)})
        assert response.status_code == 409
    outside = tmp_path / 'outside'
    outside.mkdir()
    (root/'escape').symlink_to(outside, target_is_directory=True)
    assert client.get('/admin/browse', params={'path':str(root/'escape')}).status_code == 409
    assert all(f['name'] != 'escape' for f in lib.browse(str(root))['folders'])


def test_unavailable_source_keeps_catalog_and_other_sources_scan(environment):
    client, lib, root, data = environment
    login(client, data)
    first, second = root/'A', root/'B'
    first.mkdir(); second.mkdir()
    (first/'a.mp3').write_bytes(b'a')
    (second/'b.mp3').write_bytes(b'b')
    add(client, lib, first)
    add(client, lib, second)
    first.rename(root/'offline')
    (second/'new.mp3').write_bytes(b'new')
    lib.start_scan(None)
    assert wait_for_scan(lib)['status'] == 'partial'
    assert lib.catalog()['total'] == 3
    assert any(s['error'] for s in lib.sources())


def test_reset_is_atomic_when_a_source_fails(environment):
    client, lib, root, data = environment
    login(client, data)
    first, second = root/'A', root/'B'
    first.mkdir(); second.mkdir()
    (first/'a.mp3').write_bytes(b'a')
    (second/'b.mp3').write_bytes(b'b')
    add(client, lib, first)
    add(client, lib, second)
    (first/'new.mp3').write_bytes(b'new')
    second.rename(root/'offline')
    lib.start_scan(None, reset=True)
    assert wait_for_scan(lib)['status'] == 'failed'
    assert lib.catalog()['total'] == 2


def test_scan_collision_and_remove_during_scan(environment, monkeypatch):
    client, lib, root, data = environment
    login(client, data)
    (root/'01.mp3').write_bytes(b'a')
    source = add(client, lib, root)
    entered, proceed = threading.Event(), threading.Event()
    collect = lib._collect
    def blocked(*args):
        entered.set()
        assert proceed.wait(5)
        return collect(*args)
    monkeypatch.setattr(lib, '_collect', blocked)
    lib.start_scan(source)
    assert entered.wait(5)
    try:
        assert client.post('/admin/scans', json={}).status_code == 409
        assert client.delete(f'/admin/sources/{source}').status_code == 200
    finally:
        proceed.set()
    wait_for_scan(lib)
    assert lib.catalog()['total'] == 0
    assert (root/'01.mp3').exists()


def test_partial_directory_read_does_not_delete_tracks(environment, monkeypatch):
    client, lib, root, data = environment
    login(client, data)
    (root/'one.mp3').write_bytes(b'a')
    source = add(client, lib, root)
    def failed_walk(root, onerror, followlinks):
        onerror(PermissionError('denied'))
        yield
    monkeypatch.setattr('app.library.os.walk', failed_walk)
    lib.start_scan(source)
    assert wait_for_scan(lib)['status'] == 'partial'
    assert lib.catalog()['total'] == 1


def test_restart_retains_catalog_and_marks_interrupted_scan(environment):
    client, lib, root, data = environment
    login(client, data)
    (root/'one.mp3').write_bytes(b'a')
    add(client, lib, root)
    with lib.connect() as db:
        db.execute("INSERT INTO scans(id,mode,status,started_at) VALUES('interrupted','rescan','running','2026-01-01')")
    restarted = Library(data, [root])
    assert restarted.catalog()['total'] == 1
    assert restarted.latest_scan()['status'] == 'interrupted'


def test_folders_and_pagination(environment):
    client, lib, root, data = environment
    login(client, data)
    (root/'album').mkdir()
    (root/'empty').mkdir()
    for i in range(4):
        (root/'album'/f'{i}.mp3').write_bytes(b'a')
    (root/'top.mp3').write_bytes(b'a')
    add(client, lib, root)
    result = lib.catalog(folder='album', offset=2, limit=2)
    assert result['total'] == 4
    assert len(result['items']) == 2
    assert {f['folder'] for f in result['folders']} == {'.', 'album', 'empty'}
    assert client.get('/admin/tracks?offset=-1').status_code == 422


def test_legacy_cyrillic_tags_are_read_without_changing_file(environment, monkeypatch):
    client, lib, root, data = environment
    login(client, data)
    folder = root / 'Animal ДжаZ' / '[2004] Как Люди'
    folder.mkdir(parents=True)
    file = folder / '01. Полиэтилен.mp3'
    tags = ID3()
    for frame, text in ((TIT2, 'Полиэтилен'), (TPE1, 'Animal ДжаZ'), (TALB, 'Как Люди')):
        tags.add(frame(encoding=0, text=text.encode('cp1251').decode('latin1')))
    tags.save(file)
    original_bytes = file.read_bytes()
    from mutagen.easyid3 import EasyID3
    class Audio(dict):
        info = type('Info', (), {'length': 12.5})()
    monkeypatch.setattr('app.library.File', lambda path, easy: Audio(EasyID3(path)))
    add(client, lib, root)
    track = lib.catalog()['items'][0]
    assert (track['title'], track['artist'], track['album']) == ('Полиэтилен', 'Animal ДжаZ', 'Как Люди')
    assert lib.catalog('ПОЛИЭТИЛЕН')['total'] == 1
    assert file.read_bytes() == original_bytes


@pytest.mark.parametrize('text,path', [
    ('Beyoncé', '/music/Beyoncé/01.mp3'),
    ('Motörhead', '/music/Motörhead/01.mp3'),
    ('Été', '/music/Été.mp3'),
    ('Песня', '/music/Песня.mp3'),
    ('Ïîëèýòèëåí', '/music/01.mp3'),
    ('Live', '/music/Live.mp3'),
])
def test_tag_recovery_preserves_valid_or_ambiguous_text(text, path):
    assert readable_tag(text, Path(path)) == text
