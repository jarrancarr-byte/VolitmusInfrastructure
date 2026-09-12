variable "cloudflare_account_id" {
  description = "Cloudflare account identifier."
  type        = string
}

variable "name" {
  description = "Human-readable Turnstile widget name."
  type        = string
}

variable "domains" {
  description = "Domains allowed to use the Turnstile widget. Keep sorted alphabetically."
  type        = list(string)
}
