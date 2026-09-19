param(
    [Parameter(Mandatory = $true)]
    [string]$Email,

    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"

$Email = $Email.Trim().ToLowerInvariant()
if ($Email -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') {
    throw "Invalid email address: $Email"
}

$RepoRoot = Split-Path $PSScriptRoot -Parent
$BetaDir = Join-Path $RepoRoot "environments\beta"

$TableName = (& terraform "-chdir=$BetaDir" output -raw beta_applicants_table_name).Trim()
if ($LASTEXITCODE -ne 0 -or -not $TableName) {
    throw "Could not read beta_applicants_table_name from Terraform outputs."
}

$UserPoolId = (& terraform "-chdir=$BetaDir" output -raw cognito_user_pool_id).Trim()
if ($LASTEXITCODE -ne 0 -or -not $UserPoolId) {
    throw "Could not read cognito_user_pool_id from Terraform outputs."
}

$KeyJson = @{ email = @{ S = $Email } } | ConvertTo-Json -Compress -Depth 5
$Applicant = aws dynamodb get-item `
    --region $Region `
    --table-name $TableName `
    --key $KeyJson `
    --consistent-read `
    --output json | ConvertFrom-Json

if (-not $Applicant.Item) {
    throw "No beta application exists for $Email."
}

$ExistingStatus = $Applicant.Item.status.S
Write-Host "Applicant: $Email"
Write-Host "Current status: $ExistingStatus"

if ($ExistingStatus -in @("invited", "active")) {
    Write-Host "$Email is already $ExistingStatus. No new invitation was sent."
    exit 0
}

if ($ExistingStatus -notin @("applied", "approved")) {
    throw "Applicant status '$ExistingStatus' is not eligible for Android beta invitation."
}

# Check whether the user already exists without treating UserNotFoundException as fatal.
$null = aws cognito-idp admin-get-user `
    --region $Region `
    --user-pool-id $UserPoolId `
    --username $Email `
    --output json 2>$null

if ($LASTEXITCODE -ne 0) {
    Write-Host "Creating Cognito beta user and sending invitation..."

    aws cognito-idp admin-create-user `
        --region $Region `
        --user-pool-id $UserPoolId `
        --username $Email `
        --user-attributes "Name=email,Value=$Email" "Name=email_verified,Value=true" `
        --desired-delivery-mediums EMAIL `
        --output json | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "Cognito invitation failed. DynamoDB status was not changed."
    }
}
else {
    Write-Host "Cognito user already exists; keeping the existing user."
}

$Now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$Names = '{"#status":"status"}'
$Values = @{
    ":status" = @{ S = "invited" }
    ":now"    = @{ S = $Now }
} | ConvertTo-Json -Compress -Depth 5

aws dynamodb update-item `
    --region $Region `
    --table-name $TableName `
    --key $KeyJson `
    --update-expression "SET #status = :status, invitedAt = :now, updatedAt = :now" `
    --expression-attribute-names $Names `
    --expression-attribute-values $Values `
    --output json | Out-Null

if ($LASTEXITCODE -ne 0) {
    throw "Cognito user exists, but DynamoDB status update failed."
}

Write-Host "Done. $Email is now marked invited."
