# Voltimus Infrastructure

Terraform for the Voltimus Maximus beta cloud perimeter and public beta-request API.

This tree is based on the current Git baseline and extends the existing Cognito/Cloudflare identity foundation rather than replacing it.

## What this creates

### Identity

- Amazon Cognito **Essentials** user pool for beta users
- Invite-only account creation (`AdminCreateUser` only)
- Separate public OAuth clients for the website and mobile app
- Authorization-code flow suitable for PKCE
- Refresh-token rotation and token revocation
- `auth.voltimusmaximus.com` Cognito Managed Login custom domain
- ACM certificate and Cloudflare DNS for the Cognito domain

### Public beta request API

- `api.voltimusmaximus.com` AWS API Gateway HTTP API
- Lambda request validation/storage
- `POST /beta` matching VoltimusWeb 0.3.10 Android beta requests
- `POST /ios-waitlist` matching the iOS availability form
- `GET /health` for deployment checks
- `GET /mobile-config` for the mobile beta/version gate
- DynamoDB beta applicant table with status index, PITR, encryption, and deletion protection
- API Gateway and Lambda CloudWatch logs with finite retention
- API throttling
- CORS for production VoltimusWeb plus the local port-4173 development server

### Abuse protection

- Cloudflare Turnstile widget
- Turnstile secret copied server-side into AWS Secrets Manager
- Lambda-side Turnstile Siteverify support
- Turnstile enforcement switchable with `beta_form_require_turnstile`

### Terraform state

- S3 remote-state bootstrap with versioning and native S3 lockfile support

## Deliberate beta workflow

A website request does **not** automatically create a Cognito account.

```text
voltimusmaximus.com/beta
        |
        | POST JSON
        v
api.voltimusmaximus.com/beta
        |
        v
API Gateway -> Lambda -> DynamoDB
                         status=applied
                              |
                              | human review
                              v
                     AdminCreateUser
                              |
                              v
                  Cognito invitation email
                              |
                              v
                  auth.voltimusmaximus.com
```

This keeps the initial beta controlled while still making the public form genuinely functional.

See `BETA_API.md` for the request contract and Turnstile rollout.

## What this intentionally does NOT create yet

- automatic approval of public applicants
- Cognito Identity Pool
- telemetry or precise-route upload/storage
- subscriptions/billing
- generalized authenticated feedback/crash endpoints
- a Cloudflare Worker

## Prerequisites

- Terraform 1.10+
- AWS CLI
- AWS credentials through an AWS profile, SSO, or environment variables
- Cloudflare API token in `CLOUDFLARE_API_TOKEN`
- Cloudflare Account ID and Zone ID for `voltimusmaximus.com`

The Cloudflare token needs at least:

- Account / Turnstile Sites / Edit
- Zone / DNS / Edit for `voltimusmaximus.com`

Do **not** put AWS access keys or the Cloudflare API token in `.tfvars`.

## 1. Authenticate to AWS

PowerShell:

```powershell
$env:AWS_PROFILE = "voltimus-beta"
aws sso login --profile $env:AWS_PROFILE
aws sts get-caller-identity
```

Bash:

```bash
export AWS_PROFILE=voltimus-beta
aws sso login --profile "$AWS_PROFILE"
aws sts get-caller-identity
```

## 2. Bootstrap remote state

If the state bucket was already created by the baseline infrastructure, do not recreate it. Otherwise:

```bash
cd bootstrap
terraform init
terraform apply
terraform output
```

The bucket name is deterministic:

```text
voltimus-terraform-state-<AWS_ACCOUNT_ID>
```

## 3. Configure beta

```bash
cd ../environments/beta
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example backend.hcl
```

Fill in the Cloudflare Account ID and Zone ID. Put no API tokens or AWS keys in these files.

## 4. Initialize and inspect the plan

The new beta API module introduces the `archive` provider, so the first `terraform init` may update `.terraform.lock.hcl`.

```bash
terraform init -backend-config=backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -out=beta.tfplan
```

**Inspect the plan before applying.** Existing Cognito resources should update in place or remain unchanged. Do not accept an unexpected Cognito user-pool replacement.

Then:

```bash
terraform apply beta.tfplan
terraform output
```

## 5. First beta API milestone

After apply:

```bash
curl https://api.voltimusmaximus.com/health
```

Expected:

```json
{"ok":true,"service":"voltimus-beta-api"}
```

Then run VoltimusWeb locally and submit the actual `/beta` form. The default CORS list includes `http://localhost:4173`.

Verify the application:

```bash
cd ../..
./scripts/list-beta-applicants.sh applied
```

or on Windows:

```powershell
.\scripts\list-beta-applicants.ps1 -Status applied
```

## 6. Approve a tester

Review the application first, then:

```powershell
.\scripts\approve-beta-applicant.ps1 -Email rider@example.com
```

or:

```bash
./scripts/approve-beta-applicant.sh rider@example.com
```

The script creates the Cognito user if needed and moves the applicant to `invited`.

## Turnstile

Keep Turnstile enforcement **off for the first end-to-end test** because VoltimusWeb 0.3.10 does not yet submit a Turnstile token:

```hcl
beta_form_require_turnstile = false
```

After the website integration is added, change it to `true` and re-apply.
