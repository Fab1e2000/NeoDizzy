#!/usr/bin/env python3
"""Optional fixture regeneration: pip install soundfile mutagen (not app dependencies).
Generates 0.1 seconds of silence, Chinese tags and a synthetic 1x1 PNG.
Requires macOS afconvert for the AAC fixture. No third-party music is included.
"""
import struct
import subprocess
import tempfile
import wave
import zlib
from pathlib import Path

import soundfile
from mutagen.flac import FLAC, Picture
from mutagen.id3 import ID3, TIT2, TALB, TPE1, TPE2, TRCK, TPOS, APIC, USLT
from mutagen.mp4 import MP4, MP4Cover

OUTPUT = Path(__file__).resolve().parents[1] / 'NeoDizzyTests' / 'Fixtures'


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))


png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(b'\0\xff\x99\x33')) + chunk(b'IEND', b'')
with tempfile.TemporaryDirectory() as temporary:
    wav = Path(temporary) / 'silence.wav'
    with wave.open(str(wav), 'wb') as audio:
        audio.setparams((1, 2, 44100, 4410, 'NONE', 'not compressed'))
        audio.writeframes(b'\0\0' * 4410)
    samples, rate = soundfile.read(wav)
    flac = OUTPUT / 'audio-local-tags.flac'
    soundfile.write(flac, samples, rate, format='FLAC', subtype='PCM_16')
    tags = FLAC(flac)
    tags.update(title='测试曲目', album='测试专辑', artist='曲目艺术家', albumartist='专辑艺术家', tracknumber='3', discnumber='2', lyrics='[00:00.00]测试歌词\n[00:00.05]第二行')
    picture = Picture()
    picture.type, picture.mime, picture.width, picture.height, picture.depth = 3, 'image/png', 1, 1, 24
    picture.data = png
    tags.add_picture(picture)
    tags.save()
    mp3 = OUTPUT / 'audio-local-tags.mp3'
    soundfile.write(mp3, samples, rate, format='MP3')
    tags = ID3()
    for frame, text in [(TIT2, '测试曲目'), (TALB, '测试专辑'), (TPE1, '曲目艺术家'), (TPE2, '专辑艺术家'), (TRCK, '3/10'), (TPOS, '2/2')]:
        tags.add(frame(encoding=3, text=[text]))
    tags.add(USLT(encoding=3, lang='zho', desc='', text='[00:00.00]测试歌词\n[00:00.05]第二行'))
    tags.add(APIC(encoding=3, mime='image/png', type=3, data=png))
    tags.save(mp3)
    m4a = OUTPUT / 'audio-local-tags.m4a'
    subprocess.run(['afconvert', '-f', 'm4af', '-d', 'aac', str(wav), str(m4a)], check=True)
    tags = MP4(m4a)
    tags.update({'\xa9nam': ['测试曲目'], '\xa9alb': ['测试专辑'], '\xa9ART': ['曲目艺术家'], 'aART': ['专辑艺术家'],
                 '\xa9lyr': ['[00:00.00]测试歌词\n[00:00.05]第二行'], 'trkn': [(3, 10)], 'disk': [(2, 2)], 'covr': [MP4Cover(png, imageformat=MP4Cover.FORMAT_PNG)]})
    tags.save()
