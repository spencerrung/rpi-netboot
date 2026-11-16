import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('repair', Path(__file__).with_name('update-local-boot-initramfs.py'))
repair = importlib.util.module_from_spec(spec)
spec.loader.exec_module(repair)


class BootTests(unittest.TestCase):
    def fixture(self, directory):
        root = Path(directory)
        boot = root / 'boot/firmware'
        boot.mkdir(parents=True)
        (root / 'lib/modules/6.12.test').mkdir(parents=True)
        (root / 'boot/vmlinuz-6.12.test').write_bytes(b'kernel')
        (root / 'boot/initrd.img-6.12.test').write_bytes(b'new-initramfs')
        (boot / 'kernel8.img').write_bytes(b'kernel')
        (boot / 'initrd.img').write_bytes(b'old-initramfs')
        (boot / 'config.txt').write_text('arm_64bit=1\nkernel=kernel8.img\ninitramfs initrd.img followkernel\n# preserve me\n')
        return root, boot

    def test_dry_run_then_atomic_repair_and_idempotence(self):
        with tempfile.TemporaryDirectory() as directory:
            root, boot = self.fixture(directory)
            listing = lambda _: 'usr/lib/modules/6.12.test/kernel/fs/ext4/ext4.ko\n'
            original = (boot / 'config.txt').read_text()
            repair.update(root, boot, '6.12.test', list_initramfs=listing)
            self.assertEqual((boot / 'config.txt').read_text(), original)
            self.assertFalse((boot / 'initramfs8').exists())
            repair.update(root, boot, '6.12.test', True, listing)
            self.assertEqual((boot / 'initramfs8').read_bytes(), b'new-initramfs')
            self.assertEqual((boot / 'initrd.img').read_bytes(), b'old-initramfs')
            self.assertEqual((boot / 'config.txt').read_text(), original.replace('initrd.img', 'initramfs8'))
            backups = list((root / 'root').glob('boot-initramfs-backup-*'))
            self.assertEqual(len(backups), 1)
            self.assertEqual((backups[0] / 'config.txt').read_text(), original)
            repair.update(root, boot, '6.12.test', True, listing)
            self.assertEqual(len(list((root / 'root').glob('boot-initramfs-backup-*'))), 1)

    def test_mismatched_boot_kernel_rejected_without_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root, boot = self.fixture(directory)
            (boot / 'kernel8.img').write_bytes(b'wrong-kernel')
            with self.assertRaisesRegex(ValueError, 'boot kernel'):
                repair.update(root, boot, '6.12.test', True, lambda _: '')
            self.assertFalse((boot / 'initramfs8').exists())

    def test_mismatched_initramfs_rejected_without_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            root, boot = self.fixture(directory)
            with self.assertRaisesRegex(ValueError, 'initramfs modules'):
                repair.update(root, boot, '6.12.test', True, lambda _: 'usr/lib/modules/6.6.old/kernel/fs/ext4/ext4.ko\n')
            self.assertFalse((boot / 'initramfs8').exists())


if __name__ == '__main__':
    unittest.main()
