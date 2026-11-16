#!/usr/bin/env python3
"""Stage a matched kernel/initrd/DTB/overlays for one existing NFS-boot Pi."""
import argparse
import datetime
import os
from pathlib import Path
import re
import shutil
import tempfile


def update(root, tftp, serial, kernel, apply=False):
    if not re.fullmatch(r'[0-9a-f]{8}', serial):
        raise ValueError('serial must be the final eight lowercase hexadecimal digits')
    if not re.fullmatch(r'[0-9][A-Za-z0-9.+_-]*', kernel):
        raise ValueError('invalid kernel release')
    boot = tftp / serial
    sources = {
        'kernel8.img': root / 'boot' / ('vmlinuz-' + kernel),
        'initrd.img': root / 'boot' / ('initrd.img-' + kernel),
        'bcm2711-rpi-4-b.dtb': root / 'usr/lib' / ('linux-image-' + kernel) / 'broadcom/bcm2711-rpi-4-b.dtb',
    }
    overlays = root / 'usr/lib' / ('linux-image-' + kernel) / 'overlays'
    if boot.is_symlink() or not boot.is_dir():
        raise ValueError('existing serial boot directory required; symlinks are not supported')
    for source in sources.values():
        if not source.is_file() or source.stat().st_size == 0:
            raise ValueError('missing or empty input: ' + str(source))
    if not (root / 'lib/modules' / kernel).is_dir():
        raise ValueError('matching kernel modules are missing from NFS root')
    if not overlays.is_dir() or not any(overlays.glob('*.dtbo')):
        raise ValueError('matching overlays are missing')
    config = (boot / 'config.txt').read_text()
    for line in ['kernel=kernel8.img', 'initramfs initrd.img followkernel', 'device_tree=bcm2711-rpi-4-b.dtb']:
        if line not in [x.strip() for x in config.splitlines()]:
            raise ValueError('unsupported boot configuration: ' + line)
    if 'root=/dev/nfs' not in (boot / 'cmdline.txt').read_text():
        raise ValueError('target is not configured for NFS boot')
    print('Validated matched boot inputs for', serial, kernel)
    if not apply:
        print('Dry run: no files changed. Pass --apply after backing up the node.')
        return
    backup_root = tftp.parent / 'boot-upgrade-backups'
    backup_root.mkdir(mode=0o700, exist_ok=True)
    backup = backup_root / (serial + '-' + datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ'))
    stage = Path(tempfile.mkdtemp(prefix='.' + serial + '-stage-', dir=tftp))
    try:
        shutil.copytree(boot, stage, dirs_exist_ok=True, symlinks=True)
        for name, source in sources.items():
            target = stage / name
            if target.is_symlink():
                target.unlink()
            shutil.copy2(source, target)
            # initramfs tools may create root-only images; TFTP must read them.
            target.chmod(0o644)
        target = stage / 'overlays'
        if target.is_symlink():
            target.unlink()
        elif target.exists():
            shutil.rmtree(target)
        shutil.copytree(overlays, target)
        target.chmod(0o755)
        for entry in target.rglob("*"):
            entry.chmod(0o755 if entry.is_dir() else 0o644)
        os.sync()
        boot.rename(backup)
        try:
            stage.rename(boot)
        except BaseException:
            backup.rename(boot)
            raise
        os.sync()
        print('Installed boot set. Previous boot directory retained at', backup)
        print('Reboot only this Pi, then verify uname -r and cluster readiness.')
    finally:
        if stage.exists():
            shutil.rmtree(stage)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path('/srv/nfs/raspios-pi'))
    parser.add_argument('--tftp-root', type=Path, default=Path('/opt/netboot/config/menus'))
    parser.add_argument('--serial', required=True)
    parser.add_argument('--kernel', required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    update(args.root, args.tftp_root, args.serial, args.kernel, args.apply)
