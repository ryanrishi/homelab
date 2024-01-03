cloud-init Terraform module
===

# Troubleshooting
If things aren't working, sometimes you have to go into the Proxmox UI, go to the "Cloud-Init" tab for in the VM, and then click "Regenerate image".

Cloud-init should run as expected on the next reboot.

This tends to be a problem when bringing up the sshd service. The underlying Terraform provider might not be equipped to handle cloud-init changes introduced in PVE 8.
