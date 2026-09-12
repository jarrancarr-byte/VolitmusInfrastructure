output "cognito_user_pool_id" {
  value = module.cognito.user_pool_id
}

output "cognito_issuer" {
  value = "https://cognito-idp.${var.aws_region}.amazonaws.com/${module.cognito.user_pool_id}"
}

output "cognito_web_client_id" {
  value = module.cognito.web_client_id
}

output "cognito_mobile_client_id" {
  value = module.cognito.mobile_client_id
}

output "managed_login_domain" {
  value = "https://${aws_cognito_user_pool_domain.managed_login.domain}"
}

output "turnstile_sitekey" {
  value = module.turnstile.sitekey
}

output "turnstile_secret" {
  description = "Server-side only. Never ship this in web/mobile client code."
  value       = module.turnstile.secret
  sensitive   = true
}

output "beta_api_base_url" {
  value = "https://${local.api_domain}"
}

output "beta_api_execute_endpoint" {
  description = "AWS execute-api endpoint, useful for diagnostics if custom DNS is not ready yet."
  value       = module.beta_api.execute_api_endpoint
}

output "beta_applicants_table_name" {
  value = module.beta_api.applicants_table_name
}
