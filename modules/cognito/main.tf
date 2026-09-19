resource "aws_cognito_user_pool" "this" {
  name             = "${var.name_prefix}-${var.environment}"
  user_pool_tier   = "ESSENTIALS"
  deletion_protection = "ACTIVE"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OFF"

  admin_create_user_config {
    allow_admin_create_user_only = true

    invite_message_template {
      email_subject = "Your Voltimus Maximus beta invitation"
      email_message = "You have been invited to the Voltimus Maximus beta. Sign in with {username} and temporary password {####}. You will be asked to choose a new password."
      sms_message   = "Voltimus Maximus beta: username {username}, temporary password {####}."
    }
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
  }

  tags = {
    Project     = "VoltimusMaximus"
    Environment = var.environment
    Purpose     = "BetaIdentity"
  }

  sign_in_policy {
    allowed_first_auth_factors = [
      "PASSWORD",
      "EMAIL_OTP",
    ]
  }
}

locals {
  common_client_settings = {
    scopes = ["email", "openid", "profile"]
  }
}

resource "aws_cognito_user_pool_client" "web" {
  name         = "${var.name_prefix}-${var.environment}-web"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                         = false
  allowed_oauth_flows_user_pool_client    = true
  allowed_oauth_flows                     = ["code"]
  allowed_oauth_scopes                    = local.common_client_settings.scopes
  supported_identity_providers            = ["COGNITO"]
  callback_urls                           = var.web_callback_urls
  logout_urls                             = var.web_logout_urls
  enable_token_revocation                 = true
  prevent_user_existence_errors           = "ENABLED"
  access_token_validity                   = 60
  id_token_validity                       = 60
  refresh_token_validity                  = 30

  explicit_auth_flows = [
    "ALLOW_USER_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  refresh_token_rotation {
    feature                    = "ENABLED"
    retry_grace_period_seconds = 10
  }

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

resource "aws_cognito_user_pool_client" "mobile" {
  name         = "${var.name_prefix}-${var.environment}-mobile"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                         = false
  allowed_oauth_flows_user_pool_client    = true
  allowed_oauth_flows                     = ["code"]
  allowed_oauth_scopes                    = local.common_client_settings.scopes
  supported_identity_providers            = ["COGNITO"]
  callback_urls                           = var.mobile_callback_urls
  logout_urls                             = var.mobile_logout_urls
  enable_token_revocation                 = true
  prevent_user_existence_errors           = "ENABLED"
  access_token_validity                   = 60
  id_token_validity                       = 60
  refresh_token_validity                  = 30

  explicit_auth_flows = [
    "ALLOW_USER_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]

  refresh_token_rotation {
    feature                    = "ENABLED"
    retry_grace_period_seconds = 10
  }

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}
