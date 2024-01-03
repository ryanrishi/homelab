todo
===

# General
- [x] update Plex media server
- [ ] enable hardware acceleration in Plex
- [x] migrate media VPN from OpenVPN to Wireguard
- [ ] `node_exporter` on all hosts
- [ ] `containerd` on all hosts
- [ ] update all hosts to Debian bullseye
- [ ] nimitz SNMP
- [ ] nimitz backblaze backup
- [ ] explore Loki vs. ELK
- [ ] investigate and fix Jackett/Radarr/Sonarr/Deluge setup
- [ ] automate Deluge "download complete" to Plex (+ rename?)
- [x] replace Jackett w/ Prowlarr

# Ansible
- [ ] audit `become: true` usage
- [ ] use tags instead of commenting out parts of playbooks:
  - [ ] `monitoring` for monitoring hosts and cAdvisor + node exporter
  - [ ] `media` for media hosts
- [ ] fix SSH keys

# Services
- [ ] service discovery - mostly for Prometheus config
