docker-wireguard
===

Role for [linuxserver/wireguard](https://hub.docker.com/r/linuxserver/wireguard).

Do the following after running:
1. ssh into wireguard host
2. Show Wireguard peer:
  - `docker exec -it wireguard /app/show-peer 1` - show QR code for peer 1
  - `docker exec -it wireguard cat /config/peer2/peer2.conf > ~/peer2.conf` - copy peer 2 configuration to `~/` (and then `scp` it to peer 2)
