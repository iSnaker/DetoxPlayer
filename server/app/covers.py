"""Bounded, derived JPEG covers; originals are opened only for reading."""
import hashlib
import io
import os
import threading
import warnings
from pathlib import Path

from mutagen.id3 import ID3
from PIL import Image, ImageDraw, ImageOps

MAX_BYTES = 16 * 1024 * 1024
MAX_PIXELS = 20_000_000
MAX_CACHE_FILES = 6000


def jpeg(data):
    if not data or len(data) > MAX_BYTES:
        return None
    try:
        with warnings.catch_warnings():
            warnings.simplefilter('error', Image.DecompressionBombWarning)
            with Image.open(io.BytesIO(data)) as original:
                if original.width * original.height > MAX_PIXELS:
                    return None
                original.thumbnail((512, 512))
                image = ImageOps.exif_transpose(original).convert('RGB')
                output = io.BytesIO()
                image.save(output, format='JPEG', quality=85)
                return output.getvalue()
    except (OSError, ValueError, Image.DecompressionBombError, Image.DecompressionBombWarning):
        return None


def placeholder():
    image = Image.new('RGB', (256, 256), '#182322')
    draw = ImageDraw.Draw(image)
    draw.ellipse((43, 43, 213, 213), outline='#c7f481', width=10)
    draw.ellipse((110, 110, 146, 146), fill='#c7f481')
    output = io.BytesIO()
    image.save(output, format='JPEG', quality=85)
    return output.getvalue()


class Covers:
    def __init__(self, data: Path):
        self.cache = data / 'covers'
        self.cache.mkdir(exist_ok=True)
        self.lock = threading.Lock()
        self.fallback = placeholder()

    def get(self, track_id, root, path, handle, revision=None):
        # Metadata signatures refresh covers after MP3/sidecar changes. A cached
        # image is used only after the caller has authorized and opened the track.
        info = os.fstat(handle.fileno())
        candidates, signature = [], [revision, track_id, info.st_size, info.st_mtime_ns]
        for name in ('cover.jpg', 'folder.jpg'):
            candidate = path.parent / name
            try:
                resolved = candidate.resolve(strict=True)
                if root not in resolved.parents or candidate.is_symlink():
                    continue
                stats = resolved.stat()
                signature.extend((name, stats.st_size, stats.st_mtime_ns))
                if resolved.is_file() and stats.st_size <= MAX_BYTES:
                    candidates.append(resolved)
            except (OSError, RuntimeError):
                continue
        key = hashlib.sha256(repr(signature).encode()).hexdigest()
        target = self.cache / f'{key}.jpg'
        with self.lock:
            if target.exists():
                return target.read_bytes()
            result = None
            try:
                header = handle.read(10)
                # Avoid allocating arbitrary ID3 tag sizes before Mutagen parses.
                if len(header) == 10 and header[:3] == b'ID3' and all(b < 128 for b in header[6:10]):
                    length = sum(b << (7 * (3 - i)) for i, b in enumerate(header[6:10]))
                    if length <= MAX_BYTES:
                        handle.seek(0)
                        pictures = sorted(ID3(fileobj=handle).getall('APIC'), key=lambda p: p.type != 3)
                        for picture in pictures:
                            result = jpeg(picture.data)
                            if result:
                                break
            except Exception:
                # A broken embedded picture must not prevent sidecar/fallback use.
                pass
            if result is None:
                for candidate in candidates:
                    try:
                        with candidate.open('rb') as image:
                            result = jpeg(image.read(MAX_BYTES + 1))
                        if result:
                            break
                    except OSError:
                        continue
            result = result or self.fallback
            # Bound disk use; stale signatures are evicted in small batches.
            entries = list(self.cache.glob('*.jpg'))
            if len(entries) >= MAX_CACHE_FILES:
                for old in sorted(entries, key=lambda p: p.stat().st_mtime)[:max(1, MAX_CACHE_FILES // 10)]:
                    old.unlink(missing_ok=True)
            temporary = target.with_suffix('.tmp')
            temporary.write_bytes(result)
            temporary.replace(target)
            return result
