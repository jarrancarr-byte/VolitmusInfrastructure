output "sitekey" {
  description = "Public Turnstile site key for the beta enrollment page."
  value       = cloudflare_turnstile_widget.this.sitekey
}

output "secret" {
  description = "Turnstile secret for server-side Siteverify validation. Keep this out of client code."
  value       = cloudflare_turnstile_widget.this.secret
  sensitive   = true
}
