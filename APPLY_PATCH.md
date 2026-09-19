# Apply this patch to the current VoltimusInfrastructure Git baseline

This patch was built against commit:

```text
5c730372c84a6da83d9331d7d1fa2ab5cf89d291
```

From the repository root on Windows, expand the ZIP over the checkout:

```powershell
Expand-Archive -Path C:\path\to\VoltimusInfrastructure-beta-api-patch.zip -DestinationPath . -Force
```

Then inspect:

```powershell
git status
git diff
```

Do not copy in a real `terraform.tfvars`, `backend.hcl`, AWS credential, or Cloudflare token from any ZIP.

Then:

```powershell
Set-Location .\environments\beta
terraform init -backend-config=.\backend.hcl
terraform fmt -recursive
terraform validate
terraform plan -out=.\beta.tfplan
```

Inspect the plan before apply. In particular, do not proceed if Terraform proposes replacing the existing Cognito user pool.
