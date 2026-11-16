# Updating an existing NFS-boot Pi

The initial provisioning playbook uses the kernel bundled with its OS image.
Do not rerun that playbook to upgrade an existing node: it can copy old boot
files back into the NFS root. Use this procedure for the Pi 4 NFS-boot node.

1. Back up the NFS root and the node's TFTP serial directory. Confirm which
   nodes share that root; this procedure must not race another package update.
2. Cordon the cluster node and update supported OS packages on the running Pi.
   Keep the old kernel and modules for recovery. Do not reboot yet.
3. Verify the new initramfs includes NFS networking support. On the netboot
   server, run the dry run with the exact installed kernel release:

   ```sh
   sudo python3 scripts/update-netboot-kernel.py \
     --serial c56a6028 --kernel 6.12.115+rpt-rpi-v8
   ```

4. Repeat with `--apply`. The helper validates matching kernel, initramfs,
   device tree, overlays and modules, stages the new boot set, and retains the
   previous complete serial directory outside the TFTP root. Existing firmware,
   config.txt and cmdline.txt are preserved. Never reboot during staging.
5. Reboot only the selected Pi. Verify SSH, the expected `uname -r`, NFS root,
   k3s-agent, node Ready and application health, then uncordon it.

If the node fails to boot, restore the retained serial directory on the netboot
server before power cycling the Pi. Keep the old kernel modules in the NFS root.
Boot rollback does not undo user-space package changes; retain a root backup.
This helper does not provision firmware or support Pi 5 boot layouts.
