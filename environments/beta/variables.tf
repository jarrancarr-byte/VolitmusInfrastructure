variable "aws_region" {
  description = "AWS region for the beta environment."
  type        = string
  default     = "us-east-1"
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID that owns the Turnstile widget."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for voltimusmaximus.com."
  type        = string
}

variable "root_domain" {
  description = "Primary Voltimus website domain."
  type        = string
  default     = "voltimusmaximus.com"
}

variable "auth_subdomain" {
  description = "Subdomain used for Cognito Managed Login."
  type        = string
  default     = "auth"
}

variable "api_subdomain" {
  description = "Subdomain used for the AWS beta API."
  type        = string
  default     = "api"
}

variable "web_callback_urls" {
  description = "OAuth callback URLs for the website client."
  type        = list(string)
  default     = ["https://voltimusmaximus.com/auth/callback"]
}

variable "web_logout_urls" {
  description = "Logout URLs for the website client."
  type        = list(string)
  default     = ["https://voltimusmaximus.com/"]
}

variable "mobile_callback_urls" {
  description = "OAuth callback URLs for the mobile client."
  type        = list(string)
  default     = ["voltimus://auth/callback"]
}

variable "mobile_logout_urls" {
  description = "Logout URLs for the mobile client."
  type        = list(string)
  default     = ["voltimus://logout"]
}

variable "api_allowed_origins" {
  description = "Browser origins allowed to call the beta API. Mobile clients are not subject to browser CORS."
  type        = list(string)
  default = [
    "https://voltimusmaximus.com",
    "https://www.voltimusmaximus.com",
    "http://localhost:4173",
    "http://127.0.0.1:4173"
  ]
}

variable "beta_form_require_turnstile" {
  description = "Require Turnstile on /beta and /ios-waitlist. Leave false until the deployed website sends Turnstile tokens."
  type        = bool
  default     = false
}

variable "mobile_latest_version" {
  description = "Latest Voltimus Mobile version returned by /mobile-config."
  type        = string
  default     = "0.33.79"
}

variable "mobile_latest_version_code" {
  description = "Latest Android versionCode returned by /mobile-config."
  type        = number
  default     = 198
}

variable "mobile_minimum_version_code" {
  description = "Minimum allowed Android versionCode returned by /mobile-config."
  type        = number
  default     = 198
}

variable "mobile_beta_enabled" {
  description = "Whether the mobile beta is enabled."
  type        = bool
  default     = true
}

variable "mobile_beta_message" {
  description = "Optional message returned by /mobile-config."
  type        = string
  default     = ""
}

variable "mobile_play_store_url" {
  description = "Closed-test or store URL returned by /mobile-config when available."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "CloudWatch log retention for beta API resources."
  type        = number
  default     = 30
}
