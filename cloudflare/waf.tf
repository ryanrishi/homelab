# WAF Custom Rules for Home Assistant Protection
# Free tier allows custom rules for rate limiting, bot protection, etc.

# Rate Limiting - Prevent brute force on login
resource "cloudflare_ruleset" "home_assistant_waf" {
  zone_id     = var.cloudflare_zone_id
  name        = "Home Assistant WAF Rules"
  description = "Protection rules for Home Assistant"
  kind        = "zone"
  phase       = "http_ratelimit"

  # Auth endpoint protection - most critical for preventing brute force
  # Note: Free tier limits are very restrictive (10s period, 10s timeout)
  rules {
    action = "block"
    ratelimit {
      characteristics     = ["cf.colo.id", "ip.src"]
      period              = 10  # Free tier only allows 10 second period
      requests_per_period = 2   # 2 per 10 sec = ~12 per minute
      mitigation_timeout  = 10  # Free tier only allows 10 second timeout
    }
    expression  = "(http.request.uri.path contains \"/auth/\") and (http.host eq \"${var.subdomain}.${var.domain}\")"
    description = "Rate limit authentication attempts - max 2 per 10 seconds"
    enabled     = true
  }
}

# Firewall Rules - Block known threats and bots
resource "cloudflare_ruleset" "home_assistant_firewall" {
  zone_id     = var.cloudflare_zone_id
  name        = "Home Assistant Firewall Rules"
  description = "Firewall protection for Home Assistant"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  # Block known bad bots
  rules {
    action      = "block"
    expression  = "(cf.client.bot) and (http.host eq \"${var.subdomain}.${var.domain}\")"
    description = "Block known bad bots"
    enabled     = true
  }

  # Challenge suspicious requests
  rules {
    action      = "challenge"
    expression  = "(cf.threat_score gt 10) and (http.host eq \"${var.subdomain}.${var.domain}\")"
    description = "Challenge requests with threat score > 10"
    enabled     = true
  }

  # Block all countries except USA
  rules {
    action      = "block"
    expression  = "(ip.geoip.country ne \"US\") and (http.host eq \"${var.subdomain}.${var.domain}\")"
    description = "Block all traffic except from USA"
    enabled     = true
  }
}
