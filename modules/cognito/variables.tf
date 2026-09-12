variable "name_prefix" {
  description = "Prefix for Cognito resources."
  type        = string
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "web_callback_urls" {
  description = "Allowed OAuth callback URLs for the website client."
  type        = list(string)
}

variable "web_logout_urls" {
  description = "Allowed logout URLs for the website client."
  type        = list(string)
}

variable "mobile_callback_urls" {
  description = "Allowed OAuth callback URLs for the mobile client."
  type        = list(string)
}

variable "mobile_logout_urls" {
  description = "Allowed logout URLs for the mobile client."
  type        = list(string)
}
