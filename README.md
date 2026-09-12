# Voltimus Infrastructure

Terraform for the Voltimus Maximus cloud perimeter. The first environment is `beta` and deliberately focuses on identity and enrollment protection rather than the full application backend.

## What this creates

- Amazon Cognito **Essentials** user pool for beta users
- Invite-only account creation (`AdminCreateUser` only)
- Separate public OAuth clients for the website and mobile app
- Authorization-code flow suitable for PKCE
- Refresh-token rotation and token revocation
- `auth.voltimusmaximus.com` Cognito Managed Login custom domain
- ACM certificate in `us-east-1`
- Cloudflare DNS records for ACM validation and the Cognito custom domain
- Cloudflare Turnstile widget for the Voltimus beta enrollment page
- An S3 Terraform state bucket with versioning and native S3 lockfile support

## What this intentionally does NOT create yet

- Cognito Identity Pool
- API Gateway/Lambda enrollment endpoint
- Telemetry upload/storage
- Subscription/billing resources
- A Cloudflare Worker

The next infrastructure increment should expose a small server-side beta enrollment endpoint that validates the Turnstile token and then calls Cognito `AdminCreateUser`. Until then, beta testers can be invited with the AWS console or CLI.

## Prerequisites

- Terraform 1.10+
- AWS credentials available through an AWS profile, SSO, or environment variables
- Cloudflare API token available as `CLOUDFLARE_API_TOKEN`
- Cloudflare Account ID and Zone ID for `voltimusmaximus.com`

The Cloudflare token needs at least:

- Account / Turnstile Sites / Edit
- Zone / DNS / Edit for `voltimusmaximus.com`

Do **not** put AWS access keys or the Cloudflare API token in `.tfvars`.

## 1. Authenticate to AWS

Set your normal AWS profile/SSO credentials before bootstrapping. For PowerShell:

```powershell
$env:AWS_PROFILE = "your-profile"
aws sts get-caller-identity
```

For bash:

```bash
export AWS_PROFILE=your-profile
aws sts get-caller-identity
```

## 2. Bootstrap remote state

```bash
cd bootstrap
terraform init
terraform apply
terraform output
```

The bucket name is deterministic: `voltimus-terraform-state-<AWS_ACCOUNT_ID>`.

## 3. Configure beta

```bash
cd ../environments/beta
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
```

Edit `terraform.tfvars` with your Cloudflare Account ID and Zone ID. Edit `backend.hcl` and replace the AWS account placeholder in the bucket name.

Authenticate Cloudflare without putting its token in Terraform files. PowerShell:

```powershell
$env:CLOUDFLARE_API_TOKEN = 'your-token'
```

Bash:

```bash
export CLOUDFLARE_API_TOKEN='your-token'
```

After the first successful `terraform init`, commit the generated `.terraform.lock.hcl` files so provider selections stay reproducible.

Initialize using the S3 backend:

```bash
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

## Expected beta login flow

```text
voltimusmaximus.com/beta
        |
        | Turnstile widget (enrollment protection)
        v
future server-side enrollment endpoint
        |
        | AdminCreateUser
        v
Amazon Cognito user pool
        |
        v
auth.voltimusmaximus.com
        |
        | OAuth 2.0 authorization code + PKCE
        +--------------------+
        |                    |
        v                    v
Voltimus website       Voltimus Mobile
```

## Initial callback URLs

Website:

- `https://voltimusmaximus.com/auth/callback`
- logout: `https://voltimusmaximus.com/`

Mobile:

- `voltimus://auth/callback`
- logout: `voltimus://logout`

These are variables and can be changed when the website/mobile integration is added.
# VolitmusInfrastructure
