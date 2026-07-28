# The media and molt VMs are managed outside Terraform.

locals {
  # Unfortunately `cloud_final_modules` can't be merged, only overwritten
  # This is the list from /etc/cloud/cloud.cfg with `ansible` added
  cloud_final_modules = [
    "package-update-upgrade-install",
    "fan",
    "landscape",
    "lxd",
    "write-files-deferred",
    "puppet",
    "chef",
    "ansible", # added by ryanrishi
    "mcollective",
    "salt-minion",
    "reset_rmc",
    "scripts-vendor",
    "scripts-per-once",
    "scripts-per-boot",
    "scripts-per-instance",
    "scripts-user",
    "ssh-authkey-fingerprints",
    "keys-to-console",
    "install-hotplug",
    "phone-home",
    "final-message",
    "power-state-change"
  ]
}

# Shared by every k3s node so they join the same cluster.
resource "random_password" "password" {
  length  = 16
  special = false
}
