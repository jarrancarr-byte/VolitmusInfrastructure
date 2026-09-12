locals {
  environment = "beta"
  name_prefix = "voltimus"
  auth_domain = "${var.auth_subdomain}.${var.root_domain}"

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
