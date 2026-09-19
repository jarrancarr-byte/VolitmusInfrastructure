# Voltimus beta infrastructure - Windows / PowerShell

This is the shortest path from the current Git baseline to a working website beta request.

## 1. Verify tools and AWS identity

From the repository root:

```powershell
terraform version
aws --version
$env:AWS_PROFILE = "voltimus-beta"
aws sso login --profile $env:AWS_PROFILE
aws sts get-caller-identity
```

## 2. Bootstrap only if needed

If you already created the Terraform state bucket from the earlier baseline, skip this section.

```powershell
Set-Location .\bootstrap
terraform init
terraform plan
terraform apply
terraform output
Set-Location ..
```

## 3. Configure the beta environment

```powershell
Set-Location .\environments\beta
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
Copy-Item .\backend.hcl.example .\backend.hcl
```

Get the AWS account number if needed:

```powershell
aws sts get-caller-identity --query Account --output text
```

Edit `backend.hcl` and replace the AWS-account placeholder.

Edit `terraform.tfvars` and fill in:

```text
cloudflare_account_id
cloudflare_zone_id
```

Do not put AWS credentials or the Cloudflare API token in the file.

## 4. Supply the Cloudflare credential

Use a **rotated/current** token, not any credential that appeared in an earlier review ZIP:

```powershell
$env:CLOUDFLARE_API_TOKEN = "YOUR_CURRENT_CLOUDFLARE_API_TOKEN"
```

The token needs Turnstile edit permission at the account level and DNS edit permission for `voltimusmaximus.com`.

## 5. Initialize and plan

```powershell
terraform init -backend-config=.\backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -out=.\beta.tfplan
```

The new API module adds the HashiCorp `archive` provider. The first init may update `.terraform.lock.hcl`; that is expected.

### Important plan check

The plan should add the beta API, API certificate/DNS, Lambda, DynamoDB table, logs, IAM, and Secrets Manager resource.

**Stop if Terraform proposes replacing the existing Cognito user pool.** Cognito has deletion protection, but an unexpected replacement is still a sign to inspect the plan rather than forcing it through.

Apply only after reviewing:

```powershell
terraform apply .\beta.tfplan
```

## 6. Verify outputs

```powershell
terraform output
```

Important outputs now include:

```text
cognito_user_pool_id
managed_login_domain
turnstile_sitekey
beta_api_base_url
beta_api_execute_endpoint
beta_applicants_table_name
```

The Turnstile secret remains a sensitive output and is also placed in AWS Secrets Manager for Lambda. Do not copy it into the website.

## 7. Smoke-test the API

```powershell
Invoke-RestMethod https://api.voltimusmaximus.com/health
```

Expected:

```text
ok  service
--  -------
True voltimus-beta-api
```

If custom DNS is still propagating, test the AWS endpoint first:

```powershell
$ExecuteUrl = terraform output -raw beta_api_execute_endpoint
Invoke-RestMethod "$ExecuteUrl/health"
```

## 8. Test the real website form locally

Keep the Terraform default:

```hcl
beta_form_require_turnstile = false
```

VoltimusWeb 0.3.10 currently sends no Turnstile token.

In the website repo:

```powershell
npm run dev
```

Open:

```text
http://localhost:4173/beta
```

Submit a real test request. The API's default CORS policy already permits port 4173.

Back in this infrastructure repo:

```powershell
Set-Location ..\..
.\scripts\list-beta-applicants.ps1 -Status applied
```

You should see the email, vehicle, phone model, region, and campaign fields stored in DynamoDB.

## 9. Approve the test application

```powershell
.\scripts\approve-beta-applicant.ps1 -Email "YOUR_TEST_EMAIL"
```

That creates the Cognito user if it does not already exist and updates DynamoDB to `status = invited`.

The user should receive the existing Cognito beta invitation email.
