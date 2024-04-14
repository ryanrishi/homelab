Kubernetes homelab
===

⚠️ This is a major work in progress ⚠️

My homelab evolution is as follows:
- 2013: A Raspberry Pi running SSH exposed to the internet. I was young and naive, and used this for running long-running programs that I didn't want to run on my laptop.
- 2013-2020: DigitalOcean VPS that was running my website for a while, and then replaced the Raspberry Pi mentioned above. Got increasingly sick of paying the monthly fee.
- March 2020: Suddenly had a lot more time at home, so revived a few Raspberry Pis and installed things like Grafana/InfluxDB/Telegraf, *arr services, ddclient. All managed manually via SSH. Started to use Ansible for some of these things.
- April 2020: Purchased NAS
- May 2020: Purchased NUC, installed Proxmox on NUC, started moving stuff running on Raspberry Pis to VMs on the NUC
- August 2020: Purchased second NUC and NAS combo; installed with similar setup at my parent's house. Acknowledged that all future WiFi outages would be blamed on my servers
- March 2023: Moved original NUC/NAS combo to NYC, started reviving homelab in new network environment
- November 2023: Bought first Unifi equipment; finally can have VLAN separation (IoT, homelab, everything else). Started using AdGuard on Unifi router instead of PiHole; not super impressed with AdGuard since I can't decide what to allow and what to block.
- March 2024: Decided to bite the bullet and try Kubernetes. Installed k3s on ~7 VMs (still one physical host...)
- April 2024: Finally figured out MetalLB so that I can have external IPs for k3s cluster. Plan to use this for PiHole.

Next:
- Move more stuff from VMs to k3s cluster
- Set up monitoring again

# Useful things
## Secrets Management
Secrets are backed by SOPS and a GPG key pair. I eventually want to move this to some external source like KMS, but that's a problem for another day.

To create a secret:
```sh
$ touch values.yaml
# fill out key1: value1, etc.
$ k create secret generic --namespace $NAMESPACE --from-file values.yaml $SECRET_NAME --dry-run=client -o yaml
# copy/pasta or pipe that into a file, eg. pihole-secrets.yaml
$ sops --encrypt pihole-secrets.yaml > pihole-secrets.sops.yaml
$ git add pihole-secrets.sops.yaml
# don't add pihole-secrets.yaml!
```

To decrypt a secret:
```sh
$ k get secret <name> -o yaml
# this value will be base64 encoded
$ sops --decrypt <decoded value>
```

I think this is possible in one line:
```sh
# this assumes secret is a values.yaml file. May differ for env or K/V pairs
$ k get secret <name> -o jsonpath='{.data.values\.yaml}' | base64 -d
```

To edit a secret (I haven't figured out a great way to do this):
```sh
# follow steps to decrypt secret
# edit the secret
# encrypt the secret
```

