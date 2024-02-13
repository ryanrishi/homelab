homelab 🔬
===

Ansible playbooks and Terraform modules for managing my [homelab](https://www.reddit.com/r/homelab/). You can read more about this project [here](https://ryanrishi.com/projects/homelab).

# Terraform
[`terraform/`](terraform) includes Terraform code for managing virtual machines.

# Gotchas and helpful commands
Various things I have found that I will likely forget unless I write them down here.

## cloud-init
When creating a VM via Terraform, the cloud-init doesn't run on the first boot (user error? something with the way I'm attaching the cloud-init drive? Proxmox bug?). When (re)creating a new VM, go to (VM) > Cloud-Init > Regenerate Image and then reboot the VM

---

Run a single cloud-init module
```sh
$ cloud-init single --name ansible --frequency always
```

Collect logs
```sh
# this will put a tarball in `pwd`
$ cloud-init collect-logs
```

Look at logs
```sh
$ tar -zxvf cloud-init.tar.gz
$ less cloud-init-logs-<date>/cloud-init.log
```

## k3s
Create a deployment and generate YAML for it
```sh
$ k create deployment hello-world --image hello-world -o yaml > hello-world.yml
```

# Roadmap
Here is an unprioritized list of some things I want to do next:
- Store secrets using something like Ansible vault. Need to find a way to put the vault pass in the VM before cloud-init runs
- See if I can upgrade the Debian base image. I think recent versions of cloud-init have ansible as a final module, so that would eliminate my need to override `cloud_final_modules` in my modules in [`terraform/main.tf`](terraform/main.tf)
- explore using LXC for k3s hosts to move things a little closer to the metal
- move "role" VMs (media, monitoring, etc.) into k3s - monitoring should probably have its own namespace
- be able to pass `role` in Terraform and have it generate the right Ansible cloud-init stuff. DRY things up if I make Ansible cloud-init config a first-class citizen
- figure out some best practices in deploying k3s resources. Helm? ArgoCD? `k apply -f k3s/*.yml`?
