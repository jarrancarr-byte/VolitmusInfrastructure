# Temporary beta invite procedure

Until the Turnstile-backed enrollment endpoint is added, create testers administratively.

After `terraform apply`, obtain the pool ID:

```bash
terraform output -raw cognito_user_pool_id
```

Invite a tester with AWS CLI:

```bash
aws cognito-idp admin-create-user \
  --region us-east-1 \
  --user-pool-id "$(terraform output -raw cognito_user_pool_id)" \
  --username 'tester@example.com' \
  --user-attributes Name=email,Value='tester@example.com' Name=email_verified,Value=true \
  --desired-delivery-mediums EMAIL
```

Cognito sends the beta invitation with a temporary password. The user completes the required password change through Managed Login.

Do not add beta users as `aws_cognito_user` Terraform resources. User accounts are application data, not infrastructure state.
