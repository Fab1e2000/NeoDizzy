#!/usr/bin/env python3
"""Wrap our synthetic silent audio in NCM; no account data or commercial music.

Container/cipher reference: taurusxin/ncmdump, src/ncmcrypt.cpp,
commit 4ede4cee1bad35bbf28a7b5524feeca0422a4feb. Uses openssl for AES.
"""
from pathlib import Path
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1] / 'NeoDizzyTests/Fixtures'
key = b'NeoDizzy synthetic NCM fixture'
encrypted = subprocess.run(
    ['openssl', 'enc', '-aes-128-ecb', '-K', b'hzHRAmso5kInbaxW'.hex()],
    input=b'neteasecloudmusic' + key, capture_output=True, check=True).stdout
box = list(range(256))
j = 0
for i in range(256):
    j = (box[i] + j + key[i % len(key)]) % 256
    box[i], box[j] = box[j], box[i]
mask = []
for i in range(256):
    j = (i + 1) % 256
    mask.append(box[(box[j] + box[(box[j] + j) % 256]) % 256])
u32 = lambda n: struct.pack('<I', n)
# Opaque metadata, empty image with reserved padding exercise offset handling.
metadata = b'ignored metadata'
header = (b'CTENFDAM\0\0' + u32(len(encrypted)) + bytes(b ^ 0x64 for b in encrypted)
          + u32(len(metadata)) + metadata + bytes(5) + u32(19) + u32(0) + bytes(19))
for kind in ('flac', 'mp3', 'long'):
    audio = (ROOT / f'audio-local-tags.{"flac" if kind == "long" else kind}').read_bytes()
    if kind == 'long':
        audio += bytes(i % 251 for i in range(150_003))
    payload = bytes(b ^ mask[i % 256] for i, b in enumerate(audio))
    (ROOT / f'audio-ncm-{kind}.ncm').write_bytes(header + payload)
