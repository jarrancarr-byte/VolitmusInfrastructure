# Voltimus beta infrastructure - Windows / PowerShell quick start

This is the shortest path from the project zip to the first beta infrastructure plan.

## 1. Verify tools and AWS identity

```powershell
terraform version
aws --version
$env:AWS_PROFILE = "YOUR_AWS_PROFILE"
aws sts get-caller-identity
```

If you use AWS SSO, log in to the profile first:

```powershell
aws sso login --profile $env:AWS_PROFILE
```

## 2. Create the Terraform state bucket

```powershell
Set-Location .\bootstrap
terraform init
terraform plan
terraform apply
terraform output
```

The state bucket is named:

```text
voltimus-terraform-state-<your AWS account ID>
```

## 3. Configure the beta environment

```powershell
Set-Location ..\environments\beta
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
Copy-Item .\backend.hcl.example .\backend.hcl
```

Get the AWS account number if needed:

```powershell
aws sts get-caller-identity --query Account --output text
```

Edit `backend.hcl` and replace `REPLACE_WITH_AWS_ACCOUNT_ID`.

Edit `terraform.tfvars` and fill in:

```text
cloudflare_account_id
cloudflare_zone_id
```

## 4. Supply the Cloudflare credential

Do not paste the token into a `.tf` or `.tfvars` file.

```powershell
$env:CLOUDFLARE_API_TOKEN = "YOUR_CLOUDFLARE_API_TOKEN"
```

The token should have Turnstile edit permission for the account and DNS edit permission for the `voltimusmaximus.com` zone.

## 5. Plan before applying

```powershell
terraform init -backend-config=.\backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -out=.\beta.tfplan
```

Review the plan. When it looks correct:

```powershell
terraform apply .\beta.tfplan
```

## 6. Capture integration values

```powershell
terraform output
```

The important outputs for the website/mobile integration are:

- `cognito_user_pool_id`
- `cognito_issuer`
- `cognito_web_client_id`
- `cognito_mobile_client_id`
- `managed_login_domain`
- `turnstile_sitekey`

`turnstile_secret` is sensitive and must only be used by the future server-side enrollment endpoint.

## 7. Initial tester invitations

See `INVITE_TESTER.md`. This temporary administrative flow lets us test Cognito login before wiring Turnstile into the public beta enrollment endpoint.
