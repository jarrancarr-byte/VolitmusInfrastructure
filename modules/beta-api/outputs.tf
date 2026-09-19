output "api_id" {
  value = aws_apigatewayv2_api.this.id
}

output "execute_api_endpoint" {
  value = aws_apigatewayv2_api.this.api_endpoint
}

output "api_domain_target" {
  value = aws_apigatewayv2_domain_name.this.domain_name_configuration[0].target_domain_name
}

output "api_domain_hosted_zone_id" {
  value = aws_apigatewayv2_domain_name.this.domain_name_configuration[0].hosted_zone_id
}

output "applicants_table_name" {
  value = aws_dynamodb_table.applicants.name
}

output "turnstile_secret_arn" {
  value     = aws_secretsmanager_secret.turnstile.arn
  sensitive = true
}
