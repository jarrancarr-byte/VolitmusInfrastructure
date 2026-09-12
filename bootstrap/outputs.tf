output "state_bucket_name" {
  description = "S3 bucket to use for Terraform remote state."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "beta_backend_example" {
  description = "Backend settings for the beta environment."
  value = {
    bucket       = aws_s3_bucket.terraform_state.bucket
    key          = "voltimus/beta/terraform.tfstate"
    region       = var.aws_region
    encrypt      = true
    use_lockfile = true
  }
}
