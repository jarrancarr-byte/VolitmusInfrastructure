locals {
  resource_prefix = "${var.name_prefix}-${var.environment}"

  routes = {
    "GET /health" = {}
    "GET /mobile-config" = {}
    "POST /beta" = {}
    "POST /ios-waitlist" = {}
    "POST /auth/start"   = {}
    "POST /auth/verify"  = {}
    "POST /auth/refresh" = {}
  }
}

resource "aws_dynamodb_table" "applicants" {
  name         = "${local.resource_prefix}-beta-applicants"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "email"

  attribute {
    name = "email"
    type = "S"
  }

  attribute {
    name = "status"
    type = "S"
  }

  attribute {
    name = "createdAt"
    type = "S"
  }

  global_secondary_index {
    name            = "status-createdAt"
    hash_key        = "status"
    range_key       = "createdAt"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  deletion_protection_enabled = true

  tags = {
    Purpose = "BetaApplications"
  }
}

# Terraform already receives the Turnstile secret from the Cloudflare provider.
# Keep the Lambda environment free of the raw secret by placing it in Secrets Manager.
resource "aws_secretsmanager_secret" "turnstile" {
  name                    = "${var.name_prefix}/${var.environment}/turnstile-secret"
  recovery_window_in_days = 7

  tags = {
    Purpose = "BetaTurnstile"
  }
}

resource "aws_secretsmanager_secret_version" "turnstile" {
  secret_id     = aws_secretsmanager_secret.turnstile.id
  secret_string = var.turnstile_secret
}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.root}/.terraform/voltimus-beta-api.zip"
}

resource "aws_iam_role" "lambda" {
  name = "${local.resource_prefix}-beta-api-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda" {
  name = "${local.resource_prefix}-beta-api"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.applicants.arn,
          "${aws_dynamodb_table.applicants.arn}/index/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.turnstile.arn
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminInitiateAuth",
          "cognito-idp:AdminRespondToAuthChallenge"
        ]
        Resource = "arn:aws:cognito-idp:*:*:userpool/${var.cognito_user_pool_id}"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.resource_prefix}-beta-api"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "this" {
  function_name = "${local.resource_prefix}-beta-api"
  role          = aws_iam_role.lambda.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 10
  memory_size   = 128

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  environment {
    variables = {
      APPLICANTS_TABLE             = aws_dynamodb_table.applicants.name
      TURNSTILE_SECRET_ARN         = aws_secretsmanager_secret.turnstile.arn
      TURNSTILE_REQUIRED           = tostring(var.turnstile_required)
      MOBILE_LATEST_VERSION        = var.mobile_latest_version
      MOBILE_LATEST_VERSION_CODE   = tostring(var.mobile_latest_version_code)
      MOBILE_MINIMUM_VERSION_CODE  = tostring(var.mobile_minimum_version_code)
      MOBILE_BETA_ENABLED          = tostring(var.mobile_beta_enabled)
      MOBILE_BETA_MESSAGE          = var.mobile_beta_message
      MOBILE_PLAY_STORE_URL        = var.mobile_play_store_url
      COGNITO_USER_POOL_ID     = var.cognito_user_pool_id
      COGNITO_MOBILE_CLIENT_ID = var.cognito_mobile_client_id
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_basic,
    aws_iam_role_policy.lambda,
    aws_secretsmanager_secret_version.turnstile,
  ]
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aws/apigateway/${local.resource_prefix}-beta-api"
  retention_in_days = var.log_retention_days
}

resource "aws_apigatewayv2_api" "this" {
  name          = "${local.resource_prefix}-beta-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_headers = ["Authorization", "Content-Type"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_origins = var.allowed_origins
    max_age       = 600
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.this.invoke_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 15000
}

resource "aws_apigatewayv2_route" "this" {
  for_each = local.routes

  api_id    = aws_apigatewayv2_api.this.id
  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 20
    throttling_rate_limit  = 10
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      integrationErr = "$context.integrationErrorMessage"
    })
  }
}

resource "aws_apigatewayv2_domain_name" "this" {
  domain_name = var.api_domain_name

  domain_name_configuration {
    certificate_arn = var.api_certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.this.id
  stage       = aws_apigatewayv2_stage.default.id
}
