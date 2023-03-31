Terraform + Proxmox + cloud-init = 🤌
===

In v1 of my homelab, I created a template VM by booting a Debian image, very carefully doing some manual steps like creating users, setting up disk and swap, installing base packages, etc. I would then clone that template, do more manual steps like adding reconfiguring the timezone, adding SSH keys, regenerating the VM's ssh keys, and setting the hostname.

It's been a long-term goal of mine to move away from this manual and fragile process and leverage modern tooling. I debated moving these steps to Ansible, but I would still have had to set up users and ssh keys, so I ultimately landed on using cloud-init.

This directory holds Terraform cloud for rendering cloud-init templates and creating virtual machines based on those cloud-init configuration files.

Before using this, there needs to be a Proxmox user that has adequate permissions. I followed [this guide](https://austinsnerdythings.com/2021/09/01/how-to-deploy-vms-in-proxmox-with-terraform/) to create the user.

# Usage
1. Copy the example files to their expected location. Be sure to replace the real values with the user credentials created above.
    ```sh
    $ cp env.example .env
    $ cp terraform.tfvars.example terraform.tfvars
    ```
2. Modify `main.tf` to suit your needs. You may also need to pass in `users` to the module since I've defaulted it to my needs in `modules/cloud_init/vars.tf`. You may also want to modify `cloud-init.tfpl` if you want to customize your cloud-init configuration.
3. Initialize Terraform
    ```sh
    $ tf init
    ```
4. Apply Terraform
    ```sh
    $ tf apply
    ```
    You should see Terraform at work and eventually a prompt asking "Do you want to perform these actions?". Enter `yes` if you want to do so, and watch Terraform create virtual machines that use cloud-init!

# Resources
### Resources
- [Deploy Proxmox virtual machines using Cloud-init](https://www.norocketscience.at/blog/terraform/deploy-proxmox-virtual-machines-using-cloud-init)
- [cloud-init guide](https://registry.terraform.io/providers/Telmate/proxmox/latest/docs/guides/cloud_init)
- [Proxmox cloud-init support](https://pve.proxmox.com/wiki/Cloud-Init_Support)
- [How to deploy Proxmox VMs using Terraform](https://austinsnerdythings.com/2021/09/01/how-to-deploy-vms-in-proxmox-with-terraform/)
- [@chris2k20/proxmox-cloud-init](https://github.com/chris2k20/proxmox-cloud-init)
- [Understanding cloud-init provisioning](https://forum.proxmox.com/threads/understanding-cloud-init-provisioning.95796/#post-423655)
- [How to create a Proxmox Ubuntu cloud-init image](https://austinsnerdythings.com/2021/08/30/how-to-create-a-proxmox-ubuntu-cloud-init-image/)
- [Using Terraform and Cloud-Init to deploy and automatically monitor Proxmox instances](https://yetiops.net/posts/proxmox-terraform-cloudinit-saltstack-prometheus/)
