$ErrorActionPreference = "Stop"

$Root = (Get-Location).Path
$Parent = Split-Path $Root -Parent

$OutDir = Join-Path $Parent "VoltimusInfrastructure-review"
$ZipPath = Join-Path $Parent "VoltimusInfrastructure-review.zip"

Write-Host ""
Write-Host "VoltimusInfrastructure source: $Root"
Write-Host "Review package:                $ZipPath"
Write-Host ""

if (Test-Path $OutDir) {
    Remove-Item $OutDir -Recurse -Force
}

if (Test-Path $ZipPath) {
    Remove-Item $ZipPath -Force
}

New-Item -ItemType Directory -Path $OutDir | Out-Null


# ------------------------------------------------------------
# Directories that should NEVER go into the review package
# ------------------------------------------------------------

$ExcludedDirs = @(
    ".git",
    ".terraform",
    "node_modules",
    "dist",
    ".wrangler",
    ".cache",
    "coverage",
    ".idea",
    ".vscode"
)


# ------------------------------------------------------------
# Exact sensitive/local filenames to exclude
# ------------------------------------------------------------

$ExcludedNames = @(
    ".env",
    ".dev.vars",
    "secrets.json",
    "secrets.txt",
    "credentials.json",
    "terraform.tfstate",
    "terraform.tfstate.backup",
    "backend.hcl",
    "crash.log"
)


function Is-ExcludedPath {
    param(
        [string]$RelativePath
    )

    $normalized = $RelativePath.Replace("/", "\")

    foreach ($dir in $ExcludedDirs) {
        if (
            $normalized -eq $dir -or
            $normalized.StartsWith("$dir\")
        ) {
            return $true
        }
    }

    return $false
}


function Is-Sensitive {
    param(
        [System.IO.FileInfo]$File
    )

    $name = $File.Name.ToLowerInvariant()

    # Exact sensitive filenames
    if ($ExcludedNames -contains $name) {
        return $true
    }

    # Environment files, except documented examples/templates
    if (
        $name -like ".env.*" -and
        $name -notlike "*.example" -and
        $name -notlike "*.sample" -and
        $name -notlike "*.template"
    ) {
        return $true
    }

    # Real Terraform variable files.
    # Keep example/sample/template versions.
    if (
        $name -like "*.tfvars" -and
        $name -notlike "*.example.tfvars" -and
        $name -notlike "*.sample.tfvars" -and
        $name -notlike "*.template.tfvars"
    ) {
        return $true
    }

    if (
        $name -like "*.tfvars.json" -and
        $name -notlike "*.example.tfvars.json" -and
        $name -notlike "*.sample.tfvars.json" -and
        $name -notlike "*.template.tfvars.json"
    ) {
        return $true
    }

    # Terraform state
    if (
        $name -like "*.tfstate" -or
        $name -like "*.tfstate.*"
    ) {
        return $true
    }

    # Terraform plan files
    if (
        $name -eq "tfplan" -or
        $name -like "*.tfplan" -or
        $name -like "*.plan"
    ) {
        return $true
    }

    # Private keys / certificates
    if (
        $name -like "*.pem" -or
        $name -like "*.key" -or
        $name -like "*.pfx" -or
        $name -like "*.p12"
    ) {
        return $true
    }

    # AWS credentials-style files
    if (
        $name -eq "credentials" -or
        $name -eq "config.local"
    ) {
        return $true
    }

    return $false
}


$Copied = New-Object System.Collections.Generic.List[string]
$SkippedSensitive = New-Object System.Collections.Generic.List[string]
$SkippedLarge = New-Object System.Collections.Generic.List[string]


# ------------------------------------------------------------
# Copy review-safe files
# ------------------------------------------------------------

Get-ChildItem -Path $Root -File -Recurse | ForEach-Object {

    $file = $_

    $relative = $file.FullName.Substring($Root.Length).TrimStart("\", "/")

    if (Is-ExcludedPath $relative) {
        return
    }

    if (Is-Sensitive $file) {
        $SkippedSensitive.Add($relative)
        return
    }

    # Don't package existing ZIP artifacts
    if ($file.Extension -eq ".zip") {
        return
    }

    # Skip unexpectedly large artifacts
    if ($file.Length -gt 25MB) {
        $SkippedLarge.Add($relative)
        Write-Warning "Skipping >25MB file: $relative"
        return
    }

    $dest = Join-Path $OutDir $relative
    $destDir = Split-Path $dest -Parent

    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    Copy-Item $file.FullName $dest

    $Copied.Add($relative)
}


# ------------------------------------------------------------
# Add Git context without copying .git
# ------------------------------------------------------------

$GitInfo = Join-Path $OutDir "GIT-STATUS.txt"

@(
    "VoltimusInfrastructure review package"
    "Created: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    ""
    "===== SOURCE DIRECTORY ====="
    $Root
    ""
    "===== GIT STATUS ====="
    (& git status 2>&1)
    ""
    "===== CURRENT BRANCH ====="
    (& git branch --show-current 2>&1)
    ""
    "===== CURRENT COMMIT ====="
    (& git rev-parse HEAD 2>&1)
    ""
    "===== RECENT COMMITS ====="
    (& git log --oneline --decorate -10 2>&1)
    ""
    "===== INCLUDED FILES ====="
    ($Copied | Sort-Object)
    ""
    "===== SENSITIVE FILES EXCLUDED ====="
    ($SkippedSensitive | Sort-Object)
    ""
    "===== LARGE FILES EXCLUDED ====="
    ($SkippedLarge | Sort-Object)
) | Out-File $GitInfo -Encoding utf8


# ------------------------------------------------------------
# Create ZIP
# ------------------------------------------------------------

Compress-Archive `
    -Path (Join-Path $OutDir "*") `
    -DestinationPath $ZipPath `
    -CompressionLevel Optimal


$Zip = Get-Item $ZipPath

Write-Host ""
Write-Host "Created:"
Write-Host "  $ZipPath"
Write-Host ("Size: {0:N2} MB" -f ($Zip.Length / 1MB))
Write-Host ""
Write-Host "Files included:          $($Copied.Count)"
Write-Host "Sensitive files excluded: $($SkippedSensitive.Count)"
Write-Host "Large files excluded:     $($SkippedLarge.Count)"
Write-Host ""
Write-Host "Upload VoltimusInfrastructure-review.zip here."
Write-Host ""