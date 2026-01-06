# Cloudflare Tunnel Configuration

This directory contains Terraform configuration for Cloudflare Tunnels and DNS.

## Setup

### 1. Get Cloudflare Credentials

**API Token:**
1. Go to https://dash.cloudflare.com/profile/api-tokens
2. Click "Create Token"
3. Use "Create Custom Token" with permissions:
   - **Account** - Cloudflare Tunnel: Edit
   - **Zone** - DNS: Edit
   - **Zone** - Zone: Read
4. Include your domain zone
5. Copy the token

**Account ID:**
- Found in Cloudflare dashboard URL: `dash.cloudflare.com/<account-id>/`
- Or in any domain's overview page (right sidebar)

**Zone ID:**
- Go to your domain in Cloudflare dashboard
- Scroll down in the Overview tab
- Look for "Zone ID" in the right sidebar

### 2. Create terraform.tfvars

Copy the example and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your actual values
```

**IMPORTANT:** `terraform.tfvars` is gitignored and will NOT be committed.

### 3. Initialize and Apply

```bash
terraform init
terraform plan
terraform apply
```

### 4. Get the Tunnel Token

After applying, get the tunnel token for k8s deployment:

```bash
terraform output -raw tunnel_token
```

This token will be used in the k8s cloudflared deployment (SOPS-encrypted secret).

## Resources Created

- **cloudflare_tunnel**: The tunnel infrastructure
- **cloudflare_tunnel_config**: Routes traffic from public domain to internal Home Assistant
- **cloudflare_record**: DNS CNAME record pointing to the tunnel

## Outputs

- `tunnel_token`: Sensitive token for cloudflared daemon (use in k8s secret)
- `tunnel_id`: The tunnel ID
- `homeassistant_url`: The public HTTPS URL for accessing Home Assistant
