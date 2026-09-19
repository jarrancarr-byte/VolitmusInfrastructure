# Beta API infrastructure increment

Baseline: Git commit `5c730372c84a6da83d9331d7d1fa2ab5cf89d291` from the review package supplied September 12, 2026.

## Scope

This increment leaves the existing Cognito and Turnstile modules intact and adds the smallest backend needed to make the current VoltimusWeb beta forms real:

- `api.voltimusmaximus.com`
- `GET /health`
- `GET /mobile-config`
- `POST /beta`
- `POST /ios-waitlist`
- DynamoDB applicant persistence
- API/Lambda logs and throttling
- optional server-side Turnstile verification
- PowerShell and bash applicant review/invitation scripts

The public request does not create a Cognito identity. Approval remains a deliberate administrative action.

## Website compatibility

The request parser was matched to VoltimusWeb 0.3.10 fields, including:

- Android device model/version/detection source
- vehicle and battery fields
- first/latest Metro campaign IDs
- anonymous attribution ID
- first/latest seen timestamps and landing paths
- contact consent

## Turnstile state

`beta_form_require_turnstile` defaults to `false` because VoltimusWeb 0.3.10 does not yet submit the Turnstile token. The Lambda implementation is ready for enforcement after the website integration is added.

## Validation performed in the build environment

- Python Lambda module compiled successfully.
- Offline contract tests passed for Android signup, iOS waitlist, required Android fields, mobile config, health, first-touch preservation, and no Android-data downgrade from a later iOS submission.
- All bash scripts passed `bash -n` syntax checks.
- Terraform files passed a basic delimiter/string/comment balance scan.

A full `terraform init`, `terraform validate`, and provider-backed `terraform plan` could not be run in the build environment because the Terraform CLI/providers were not available there. Run those commands locally before apply, and stop if the plan proposes replacing the existing Cognito user pool.
