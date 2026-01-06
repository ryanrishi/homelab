# Output the tunnel token (needed for cloudflared deployment)
output "tunnel_token" {
  description = "Tunnel token for cloudflared (sensitive - use for k8s secret)"
  value       = cloudflare_zero_trust_tunnel_cloudflared.homeassistant.tunnel_token
  sensitive   = true
}

output "tunnel_id" {
  description = "Cloudflare Tunnel ID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.homeassistant.id
}

output "tunnel_cname" {
  description = "CNAME target for the tunnel"
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.homeassistant.id}.cfargotunnel.com"
}

output "homeassistant_url" {
  description = "Public HTTPS URL for Home Assistant"
  value       = "https://${var.subdomain}.${var.domain}"
  sensitive   = true
}
