# Beta applicant approval and Cognito invitation

The preferred beta flow now begins with a website application in DynamoDB. Do not automatically turn every public submission into a Cognito account.

## Review applicants

From the repository root:

PowerShell:

```powershell
.\scripts\list-beta-applicants.ps1 -Status applied
```

Bash:

```bash
./scripts/list-beta-applicants.sh applied
```

## Invite an approved tester

PowerShell:

```powershell
.\scripts\approve-beta-applicant.ps1 -Email tester@example.com
```

Bash:

```bash
./scripts/approve-beta-applicant.sh tester@example.com
```

The script:

1. verifies that the email exists in the beta applicant table,
2. creates the Cognito user if it does not already exist,
3. lets Cognito send the beta invitation email,
4. updates the application to `status = invited` with an invitation timestamp.

Cognito sends a temporary password using the existing invite template. The tester completes the required password change through Managed Login.

Do not add beta users as `aws_cognito_user` Terraform resources. User accounts are application data, not infrastructure state.
