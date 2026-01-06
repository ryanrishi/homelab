# Cloudflare API credentials
variable "cloudflare_api_token" {
  description = "Cloudflare API token with Tunnel and DNS permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for your domain"
  type        = string
  sensitive   = true
}

# Domain configuration
variable "domain" {
  description = "Base domain name"
  type        = string
  sensitive   = true
}

variable "subdomain" {
  description = "Subdomain for the tunnel (e.g., 'homeassistant.nyc')"
  type        = string
  sensitive   = true
}

# Home Assistant configuration
variable "homeassistant_url" {
  description = "Internal URL for Home Assistant (e.g., 'http://192.168.4.231:8123')"
  type        = string
  default     = "http://192.168.4.231:8123"
}

variable "tunnel_name" {
  description = "Name for the Cloudflare Tunnel"
  type        = string
  default     = "homeassistant-tunnel"
}
