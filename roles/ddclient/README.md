ddclient
===

Update dynamic DNS entries

Heavily adapted from [jpartain89/ansible-role-ddclient](https://github.com/jpartain89/ansible-role-ddclient)

# Setup
## Cloudflare
1. Add a domain to Cloudflare.
2. Create an A record with the following:
```yaml
Type: A
Name: example.com   # enter @ for root domain
Content: 
TTL: Auto
Proxy status: DNS only
```
3. Get your Cloudflare API key (`My Profile` > `API Tokens` > `Global API Key`). Set this in the `password` entry in your vars file.
