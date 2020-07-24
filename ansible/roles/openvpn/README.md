Heavily copied from [beenje/pi_openvpn](https://github.com/beenje/pi_openvpn)

### Notes
Create a Diffie-Helman key before running this:
```
$ cd /tmp
$ wget https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.6/EasyRSA-unix-v3.0.6.tgz
$ tar xfz EasyRSA-unix-v3.0.6.tgz
$ cd EasyRSA-v3.0.6
$ ./easyrsa init-pki
$ ./easyrsa gen-dh
```
And then set `openvpn_dh` to the path of the key
