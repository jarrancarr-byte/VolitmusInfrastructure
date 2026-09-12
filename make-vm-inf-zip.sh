#!/usr/bin/env bash
set -euo pipefail

SOURCE="$(pwd)"
PARENT="$(dirname "$SOURCE")"
OUTPUT="$PARENT/VoltimusInfrastructure-review"
ZIP="$PARENT/VoltimusInfrastructure-review.zip"

echo "Source: $SOURCE"
echo "Output: $OUTPUT"

rm -rf "$OUTPUT"
rm -f "$ZIP"
mkdir -p "$OUTPUT"

copied=0
sensitive=0

is_excluded_dir() {
    local path="$1"

    case "$path" in
        .git/*|\
        .terraform/*|\
        .terragrunt-cache/*|\
        node_modules/*|\
        dist/*|\
        build/*|\
        out/*|\
        coverage/*|\
        .next/*|\
        .cache/*|\
        .parcel-cache/*|\
        cdk.out/*|\
        .serverless/*|\
        .aws-sam/*|\
        .idea/*|\
        .gradle/*|\
        target/*|\
        bin/*|\
        obj/*|\
        __pycache__/*|\
        .pytest_cache/*|\
        .mypy_cache/*|\
        .venv/*|\
        venv/*)
            return 0
            ;;
    esac

    return 1
}

is_sensitive() {
    local path="$1"
    local name
    name="$(basename "$path")"

    # Actual environment files.
    case "$name" in
        .env.example|.env.sample|.env.template)
            ;;
        .env|.env.*)
            return 0
            ;;
    esac

    # Terraform state can contain secrets.
    case "$name" in
        *.tfstate|*.tfstate.*)
            return 0
            ;;
    esac

    # Real variable files may contain secrets.
    # Keep obvious templates/examples.
    case "$name" in
        *.tfvars.example|\
        *.tfvars.sample|\
        *.tfvars.template|\
        *.auto.tfvars.example|\
        *.auto.tfvars.sample|\
        *.auto.tfvars.template)
            ;;
        *.tfvars|*.auto.tfvars)
            return 0
            ;;
    esac

    # Keys, certificates, and credential stores.
    case "$name" in
        *.pem|\
        *.key|\
        *.p12|\
        *.pfx|\
        *.jks|\
        *.keystore|\
        credentials|\
        credentials.json|\
        secrets.json|\
        secret.json)
            return 0
            ;;
    esac

    return 1
}

is_allowed() {
    local path="$1"
    local name
    name="$(basename "$path")"

    case "$name" in
        Dockerfile|\
        Makefile|\
        Procfile|\
        .gitignore|\
        .dockerignore|\
        package.json|\
        package-lock.json|\
        npm-shrinkwrap.json|\
        yarn.lock|\
        pnpm-lock.yaml|\
        tsconfig.json|\
        cdk.json|\
        serverless.yml|\
        serverless.yaml|\
        template.yml|\
        template.yaml|\
        samconfig.toml|\
        requirements.txt|\
        pyproject.toml|\
        poetry.lock|\
        Pipfile|\
        Pipfile.lock|\
        go.mod|\
        go.sum|\
        Cargo.toml|\
        Cargo.lock|\
        gradlew|\
        gradlew.bat)
            return 0
            ;;
    esac

    case "$name" in
        *.tf|\
        *.hcl|\
        *.ts|\
        *.tsx|\
        *.js|\
        *.jsx|\
        *.mjs|\
        *.cjs|\
        *.py|\
        *.go|\
        *.java|\
        *.kt|\
        *.sh|\
        *.ps1|\
        *.sql|\
        *.graphql|\
        *.gql|\
        *.json|\
        *.yaml|\
        *.yml|\
        *.toml|\
        *.md|\
        *.txt|\
        *.properties|\
        *.example|\
        *.sample|\
        *.template)
            return 0
            ;;
    esac

    return 1
}

included_file="$OUTPUT/REVIEW-INCLUDED.txt"
sensitive_file="$OUTPUT/REVIEW-SENSITIVE-EXCLUDED.txt"

: > "$included_file"
: > "$sensitive_file"

while IFS= read -r -d '' file; do
    rel="${file#"$SOURCE"/}"

    if is_excluded_dir "$rel"; then
        continue
    fi

    if is_sensitive "$rel"; then
        printf '%s\n' "$rel" >> "$sensitive_file"
        sensitive=$((sensitive + 1))
        continue
    fi

    if ! is_allowed "$rel"; then
        continue
    fi

    # Skip unusually large generated text/config files.
    size="$(stat -c '%s' "$file")"

    if (( size > 10485760 )); then
        echo "Skipping >10 MB file: $rel"
        continue
    fi

    dest="$OUTPUT/$rel"
    mkdir -p "$(dirname "$dest")"
    cp -p "$file" "$dest"

    printf '%s\n' "$rel" >> "$included_file"
    copied=$((copied + 1))

done < <(find "$SOURCE" -type f -print0)

{
    echo "VoltimusInfrastructure review package"
    echo "Created: $(date -Iseconds)"
    echo
    echo "Source:"
    echo "$SOURCE"
    echo
    echo "Files included: $copied"
    echo "Sensitive files excluded: $sensitive"
} > "$OUTPUT/REVIEW-SUMMARY.txt"

sort -o "$included_file" "$included_file"
sort -o "$sensitive_file" "$sensitive_file"

echo
echo "Copied $copied source/configuration files."
echo "Excluded $sensitive potentially sensitive files."

if command -v zip >/dev/null 2>&1; then
    (
        cd "$OUTPUT"
        zip -qr "$ZIP" .
    )

    echo
    echo "Created:"
    echo "  $ZIP"
    du -h "$ZIP"
else
    echo
    echo "'zip' is not installed."
    echo "Install it with:"
    echo "  sudo apt install zip"
    echo
    echo "Then run:"
    echo "  cd \"$OUTPUT\""
    echo "  zip -r \"$ZIP\" ."
fi
