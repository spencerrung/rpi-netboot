import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('upgrade', Path(__file__).parents[1] / 'scripts/update-netboot-kernel.py')
upgrade = importlib.util.module_from_spec(spec)
spec.loader.exec_module(upgrade)


class UpgradeTest(unittest.TestCase):
    def test_dry_run_missing_inputs_and_retained_rollback(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            root, tftp = base / 'root', base / 'tftp'
            serial, kernel = 'c56a6028', '6.12.115+rpt-rpi-v8'
            boot = tftp / serial
            boot.mkdir(parents=True)
            (boot / 'config.txt').write_text('kernel=kernel8.img\ninitramfs initrd.img followkernel\ndevice_tree=bcm2711-rpi-4-b.dtb\n')
            (boot / 'cmdline.txt').write_text('root=/dev/nfs nfsroot=server:/root')
            (boot / 'kernel8.img').write_text('old kernel')
            (boot / 'start4.elf').write_text('existing firmware')
            with self.assertRaises(ValueError):
                upgrade.update(root, tftp, serial, kernel, True)
            self.assertEqual((boot / 'kernel8.img').read_text(), 'old kernel')
            for name in ['boot/vmlinuz-' + kernel, 'boot/initrd.img-' + kernel,
                         'usr/lib/linux-image-' + kernel + '/broadcom/bcm2711-rpi-4-b.dtb',
                         'usr/lib/linux-image-' + kernel + '/overlays/test.dtbo']:
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('new ' + name)
                p.chmod(0o600)
            (root / 'lib/modules' / kernel).mkdir(parents=True)
            upgrade.update(root, tftp, serial, kernel)
            self.assertEqual((boot / 'kernel8.img').read_text(), 'old kernel')
            upgrade.update(root, tftp, serial, kernel, True)
            self.assertEqual((boot / 'kernel8.img').read_text(), 'new boot/vmlinuz-' + kernel)
            self.assertEqual((boot / 'start4.elf').read_text(), 'existing firmware')
            backups = list((base / 'boot-upgrade-backups').iterdir())
            self.assertEqual(len(backups), 1)
            self.assertEqual((backups[0] / 'kernel8.img').read_text(), 'old kernel')
            self.assertEqual((boot / 'cmdline.txt').read_text(), (backups[0] / 'cmdline.txt').read_text())
            self.assertTrue((boot / 'overlays/test.dtbo').exists())
            for name in ['kernel8.img', 'initrd.img', 'bcm2711-rpi-4-b.dtb', 'overlays/test.dtbo']:
                self.assertEqual((boot / name).stat().st_mode & 0o777, 0o644)


if __name__ == '__main__':
    unittest.main()
