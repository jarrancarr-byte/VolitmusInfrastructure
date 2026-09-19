locals {
  environment = "beta"
  name_prefix = "voltimus"
  auth_domain = "${var.auth_subdomain}.${var.root_domain}"
  api_domain  = "${var.api_subdomain}.${var.root_domain}"

  turnstile_domains = sort([
    var.root_domain,
    "www.${var.root_domain}"
  ])
}

module "cognito" {
  source = "../../modules/cognito"

  name_prefix          = local.name_prefix
  environment          = local.environment
  web_callback_urls    = var.web_callback_urls
  web_logout_urls      = var.web_logout_urls
  mobile_callback_urls = var.mobile_callback_urls
  mobile_logout_urls   = var.mobile_logout_urls
}

module "turnstile" {
  source = "../../modules/turnstile"

  cloudflare_account_id = var.cloudflare_account_id
  name                  = "Voltimus Maximus Beta Enrollment"
  domains               = local.turnstile_domains
}

resource "aws_acm_certificate" "cognito_domain" {
  provider          = aws.us_east_1
  domain_name       = local.auth_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_dns_record" "acm_validation" {
  for_each = {
    for option in aws_acm_certificate.cognito_domain.domain_validation_options :
    option.domain_name => option
  }

  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(each.value.resource_record_name, ".")
  content = trimsuffix(each.value.resource_record_value, ".")
  type    = each.value.resource_record_type
  ttl     = 60
  proxied = false
  comment = "Terraform-managed ACM validation for ${local.auth_domain}"
}

resource "aws_acm_certificate_validation" "cognito_domain" {
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.cognito_domain.arn

  validation_record_fqdns = [
    for record in cloudflare_dns_record.acm_validation : record.name
  ]
}

resource "aws_cognito_user_pool_domain" "managed_login" {
  domain                = local.auth_domain
  user_pool_id          = module.cognito.user_pool_id
  certificate_arn       = aws_acm_certificate_validation.cognito_domain.certificate_arn
  managed_login_version = 2
}

# Keep Cognito DNS-only (gray cloud). Cloudflare resolves the hostname but
# does not reverse-proxy Cognito's Managed Login traffic.
resource "cloudflare_dns_record" "cognito_auth" {
  zone_id = var.cloudflare_zone_id
  name    = local.auth_domain
  content = aws_cognito_user_pool_domain.managed_login.cloudfront_distribution
  type    = "CNAME"
  ttl     = 60
  proxied = false
  comment = "Voltimus Cognito Managed Login custom domain"
}

# App clients created through Terraform/API do not receive a Managed Login
# branding style automatically. Assign Cognito's default style explicitly.
resource "aws_cognito_managed_login_branding" "web" {
  user_pool_id                = module.cognito.user_pool_id
  client_id                   = module.cognito.web_client_id
  use_cognito_provided_values = true

  depends_on = [aws_cognito_user_pool_domain.managed_login]
}

resource "aws_cognito_managed_login_branding" "mobile" {
  user_pool_id                = module.cognito.user_pool_id
  client_id                   = module.cognito.mobile_client_id
  use_cognito_provided_values = true

  depends_on = [aws_cognito_user_pool_domain.managed_login]
}

# API Gateway regional custom-domain certificates must live in the same AWS
# region as the HTTP API. This uses the default beta AWS provider/region.
resource "aws_acm_certificate" "api_domain" {
  domain_name       = local.api_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_dns_record" "api_acm_validation" {
  for_each = {
    for option in aws_acm_certificate.api_domain.domain_validation_options :
    option.domain_name => option
  }

  zone_id = var.cloudflare_zone_id
  name    = trimsuffix(each.value.resource_record_name, ".")
  content = trimsuffix(each.value.resource_record_value, ".")
  type    = each.value.resource_record_type
  ttl     = 60
  proxied = false
  comment = "Terraform-managed ACM validation for ${local.api_domain}"
}

resource "aws_acm_certificate_validation" "api_domain" {
  certificate_arn = aws_acm_certificate.api_domain.arn

  validation_record_fqdns = [
    for record in cloudflare_dns_record.api_acm_validation : record.name
  ]
}

module "beta_api" {
  source = "../../modules/beta-api"

  name_prefix         = local.name_prefix
  environment         = local.environment
  api_domain_name     = local.api_domain
  api_certificate_arn = aws_acm_certificate_validation.api_domain.certificate_arn
  allowed_origins     = var.api_allowed_origins

  turnstile_secret   = module.turnstile.secret
  turnstile_required = var.beta_form_require_turnstile

  mobile_latest_version       = var.mobile_latest_version
  mobile_latest_version_code  = var.mobile_latest_version_code
  mobile_minimum_version_code = var.mobile_minimum_version_code
  mobile_beta_enabled         = var.mobile_beta_enabled
  mobile_beta_message         = var.mobile_beta_message
  mobile_play_store_url       = var.mobile_play_store_url
  log_retention_days          = var.log_retention_days
  cognito_user_pool_id        = module.cognito.user_pool_id
  cognito_mobile_client_id    = module.cognito.mobile_client_id
}

# Keep the API hostname DNS-only. API Gateway terminates TLS using the
# validated ACM certificate; Cloudflare remains authoritative DNS.
resource "cloudflare_dns_record" "api" {
  zone_id = var.cloudflare_zone_id
  name    = local.api_domain
  content = module.beta_api.api_domain_target
  type    = "CNAME"
  ttl     = 60
  proxied = false
  comment = "Voltimus AWS beta API custom domain"
}