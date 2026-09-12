variable "aws_region" {
  description = "AWS region for the Cognito beta user pool."
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
