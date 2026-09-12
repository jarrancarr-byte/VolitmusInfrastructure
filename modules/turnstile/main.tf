resource "cloudflare_turnstile_widget" "this" {
  account_id = var.cloudflare_account_id
  name       = var.name
  domains    = var.domains
  mode       = "managed"
  region     = "world"
}
