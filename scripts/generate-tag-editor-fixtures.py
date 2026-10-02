#!/usr/bin/env python3
"""Optional: pip install mutagen. Adds preservation fixtures to existing synthetic audio."""
from pathlib import Path
import shutil
import struct
import zlib
from mutagen.flac import FLAC, Picture
from mutagen.id3 import ID3, TXXX, APIC
from mutagen.mp4 import MP4, MP4Cover, MP4FreeForm

root = Path(__file__).resolve().parents[1] / 'NeoDizzyTests/Fixtures'
def chunk(kind, value):
    return struct.pack('>I', len(value)) + kind + value + struct.pack('>I', zlib.crc32(kind + value))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(b'\0\x33\x66\xff')) + chunk(b'IEND', b'')
(root / 'tag-cover-replacement.png').write_bytes(png)
for ext in ['flac', 'mp3', 'm4a']:
    path = root / ('audio-tag-preservation.' + ext)
    shutil.copyfile(root / ('audio-local-tags.' + ext), path)
    if ext == 'flac':
        audio = FLAC(path)
        audio['UNTOUCHED_CUSTOM'] = ['保留此字段']
        picture = Picture()
        picture.type, picture.mime, picture.desc, picture.width, picture.height, picture.depth = 4, 'image/png', 'Back', 1, 1, 24
        picture.data = png
        audio.add_picture(picture)
    elif ext == 'mp3':
        audio = ID3(path)
        audio.add(TXXX(encoding=3, desc='UntouchedCustom', text=['保留此字段']))
        audio.add(APIC(encoding=3, mime='image/png', type=4, desc='Back', data=png))
    else:
        audio = MP4(path)
        audio['----:org.neodizzy:UntouchedCustom'] = [MP4FreeForm('保留此字段'.encode())]
        audio['covr'].append(MP4Cover(png, imageformat=MP4Cover.FORMAT_PNG))
    audio.save(path)
