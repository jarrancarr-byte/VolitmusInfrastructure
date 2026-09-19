variable "name_prefix" {
  description = "Prefix for beta API resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "api_domain_name" {
  description = "Fully-qualified API custom domain name."
  type        = string
}

variable "api_certificate_arn" {
  description = "Validated ACM certificate ARN for the API custom domain."
  type        = string
}

variable "allowed_origins" {
  description = "Browser origins allowed by API Gateway CORS."
  type        = list(string)
}

variable "turnstile_secret" {
  description = "Cloudflare Turnstile server secret."
  type        = string
  sensitive   = true
}

variable "turnstile_required" {
  description = "Require a valid Turnstile token on public signup endpoints. Leave false until VoltimusWeb sends the token."
  type        = bool
  default     = false
}

variable "mobile_latest_version" {
  description = "Latest mobile version returned by /mobile-config."
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
  description = "Whether the mobile beta is currently enabled."
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
  description = "CloudWatch log retention for the beta API."
  type        = number
  default     = 30
}

variable "cognito_user_pool_id" {
  description = "Cognito user pool used for Voltimus beta authentication."
  type        = string
}

variable "cognito_mobile_client_id" {
  description = "Cognito public mobile client used for Voltimus beta authentication."
  type        = string
}