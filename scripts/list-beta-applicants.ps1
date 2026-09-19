param(
    [ValidateSet("ios_waitlist", "applied", "approved", "invited", "active", "declined")]
    [string]$Status = "applied",

    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot -Parent
$BetaDir = Join-Path $RepoRoot "environments\beta"

$TableName = (& terraform "-chdir=$BetaDir" output -raw beta_applicants_table_name).Trim()
if ($LASTEXITCODE -ne 0 -or -not $TableName) {
    throw "Could not read beta_applicants_table_name from Terraform outputs."
}

$Values = @{ ":status" = @{ S = $Status } } | ConvertTo-Json -Compress -Depth 5

aws dynamodb query `
    --region $Region `
    --table-name $TableName `
    --index-name status-createdAt `
    --key-condition-expression "#status = :status" `
    --expression-attribute-names '{"#status":"status"}' `
    --expression-attribute-values $Values `
    --no-scan-index-forward `
    --query 'Items[].{Email:email.S,Status:status.S,Created:createdAt.S,Platform:platform.S,Vehicle:vehicleModel.S,Phone:deviceModel.S,Android:androidVersion.S,Battery:batteryVoltage.S,Region:region.S,FirstAd:firstAdId.S,LatestAd:latestAdId.S}' `
    --output table
