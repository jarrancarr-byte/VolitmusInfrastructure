param(
    [string]$BaseUrl = "",
    [string]$Email = ""
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path $PSScriptRoot -Parent
$BetaDir = Join-Path $RepoRoot "environments\beta"

if (-not $BaseUrl) {
    $BaseUrl = (& terraform "-chdir=$BetaDir" output -raw beta_api_base_url).Trim()
}

$BaseUrl = $BaseUrl.TrimEnd('/')

Write-Host "GET $BaseUrl/health"
$Health = Invoke-RestMethod "$BaseUrl/health"
$Health | Format-List

Write-Host "GET $BaseUrl/mobile-config"
$Config = Invoke-RestMethod "$BaseUrl/mobile-config"
$Config | Format-List

if ($Email) {
    Write-Host "Submitting Android smoke-test application for $Email"
    $Payload = @{
        signupType = "android_beta"
        platform = "Android"
        email = $Email
        vehicleModel = "Infrastructure smoke test"
        deviceModel = "Windows smoke test"
        androidVersion = "test"
        deviceDetectionSource = "manual"
        batteryVoltage = "60V"
        region = "smoke-test"
        contactConsent = $true
        firstAdId = "smoketest"
        latestAdId = "smoketest"
        anonymousId = "smoke-test"
        attribution = @{
            firstAdId = "smoketest"
            latestAdId = "smoketest"
            anonymousId = "smoke-test"
            firstSeenAt = (Get-Date).ToUniversalTime().ToString("o")
            latestSeenAt = (Get-Date).ToUniversalTime().ToString("o")
            firstLandingPath = "/beta?adid=smoketest"
            latestLandingPath = "/beta?adid=smoketest"
        }
    } | ConvertTo-Json -Depth 5

    Invoke-RestMethod `
        -Method Post `
        -Uri "$BaseUrl/beta" `
        -ContentType "application/json" `
        -Body $Payload | Format-List
}
else {
    Write-Host "No -Email supplied; signup write test skipped."
}
