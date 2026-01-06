# Generate a random secret for the tunnel
resource "random_id" "tunnel_secret" {
  byte_length = 32
}

# Create the Cloudflare Tunnel
resource "cloudflare_tunnel" "homeassistant" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  secret     = random_id.tunnel_secret.b64_std
}

# Configure the tunnel to route traffic to Home Assistant
resource "cloudflare_tunnel_config" "homeassistant" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_tunnel.homeassistant.id

  config {
    ingress_rule {
      hostname = "${var.subdomain}.${var.domain}"
      service  = var.homeassistant_url
    }

    # Catch-all rule (required by Cloudflare)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Create DNS record pointing to the tunnel
resource "cloudflare_record" "homeassistant" {
  zone_id = var.cloudflare_zone_id
  name    = var.subdomain
  value   = "${cloudflare_tunnel.homeassistant.id}.cfargotunnel.com"
  type    = "CNAME"
  proxied = true
  comment = "Cloudflare Tunnel for Home Assistant"
}
