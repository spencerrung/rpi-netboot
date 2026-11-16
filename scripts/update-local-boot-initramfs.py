#!/usr/bin/env python3
"""Align an SD-boot Pi's explicit initramfs name with Raspberry Pi OS updates."""
import argparse
import datetime
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def replace_file(path, source=None, text=None):
    fd, temporary = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            if source is not None:
                with source.open('rb') as original:
                    shutil.copyfileobj(original, stream)
            else:
                stream.write(text.encode())
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        Path(temporary).unlink(missing_ok=True)


def update(root, boot, kernel, apply=False, list_initramfs=None):
    if not re.fullmatch(r'[0-9][A-Za-z0-9.+_-]*', kernel):
        raise ValueError('invalid kernel release')
    source_kernel = root / 'boot' / ('vmlinuz-' + kernel)
    source_initrd = root / 'boot' / ('initrd.img-' + kernel)
    for path in [source_kernel, source_initrd, boot / 'kernel8.img', boot / 'config.txt']:
        if path.is_symlink() or not path.is_file() or not path.stat().st_size:
            raise ValueError('nonempty regular file required: ' + str(path))
    if not (root / 'lib/modules' / kernel).is_dir():
        raise ValueError('matching root-filesystem kernel modules are missing')
    if digest(source_kernel) != digest(boot / 'kernel8.img'):
        raise ValueError('boot kernel does not match the requested kernel release')
    config = (boot / 'config.txt').read_text()
    active = [line.strip() for line in config.splitlines() if line.strip() and not line.lstrip().startswith('#')]
    if [line for line in active if line.startswith('kernel=')] != ['kernel=kernel8.img']:
        raise ValueError('expected exactly one explicit kernel=kernel8.img setting')
    directives = [line for line in active if line.startswith('initramfs ')]
    if directives not in [['initramfs initrd.img followkernel'], ['initramfs initramfs8 followkernel']]:
        raise ValueError('unsupported or ambiguous initramfs setting')
    listing = (list_initramfs or (lambda p: subprocess.check_output(['lsinitramfs', str(p)], text=True)))(source_initrd)
    releases = set(re.findall(r'(?:^|/)lib/modules/([^/\n]+)', listing, re.MULTILINE))
    if releases != {kernel}:
        raise ValueError('initramfs modules do not match the requested kernel: ' + repr(releases))
    print('Validated boot kernel, root modules and initramfs for', kernel)
    new_config = re.sub(r'(?m)^(\s*)initramfs initrd\.img followkernel\s*$', r'\1initramfs initramfs8 followkernel', config)
    target = boot / 'initramfs8'
    if target.exists() and (target.is_symlink() or not target.is_file()):
        raise ValueError('initramfs8 must be a regular file')
    if new_config == config and target.exists() and digest(target) == digest(source_initrd):
        print('Boot configuration already uses the matching package-managed initramfs')
        return
    if not apply:
        print('Dry run: would install matching initramfs8 and update the explicit initramfs directive')
        return
    backup = root / 'root' / ('boot-initramfs-backup-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    backup.mkdir(parents=True, mode=0o700)
    shutil.copy2(boot / 'config.txt', backup / 'config.txt')
    if target.exists():
        shutil.copy2(target, backup / 'initramfs8')
    replace_file(target, source=source_initrd)
    if digest(target) != digest(source_initrd):
        raise RuntimeError('installed initramfs checksum mismatch; configuration was not changed')
    replace_file(boot / 'config.txt', text=new_config)
    os.sync()
    print('Installed matching initramfs8; previous configuration retained at', backup)
    print('Old initrd.img and kernel files are retained. Boot order was not changed.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path('/'))
    parser.add_argument('--boot', type=Path, default=Path('/boot/firmware'))
    parser.add_argument('--kernel', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    update(args.root, args.boot, args.kernel, args.apply)
