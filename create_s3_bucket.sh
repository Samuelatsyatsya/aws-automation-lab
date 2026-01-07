#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="create_s3_bucket.log"

# Configuration
BUCKET_PREFIX="automationlab-bucket"
SAMPLE_FILE="welcome.txt"
PROJECT_TAG="AutomationLab"
REGION=$(aws configure get region)

log() {
    local LEVEL="${2:-INFO}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$LEVEL] : $1" | tee -a "$LOG_FILE" >&2
}

error_exit() {
    log "$1" "ERROR"
    exit 1
}

check_prerequisites() {
    command -v aws >/dev/null 2>&1 || error_exit "AWS CLI not installed."
    aws sts get-caller-identity >/dev/null 2>&1 || error_exit "AWS credentials not configured or invalid."
}

# ---------------- GENERIC RESOURCE ENSURER ----------------
# For S3 bucket: check if bucket exists, create if not
ensure_s3_bucket() {
    local bucket_name="$1"

    EXISTS=$(aws s3api head-bucket --bucket "$bucket_name" 2>/dev/null || true)

    if [[ -z "$EXISTS" ]]; then
        aws s3api create-bucket --bucket "$bucket_name" --region "$REGION" --create-bucket-configuration LocationConstraint="$REGION"
        log "Created S3 bucket: $bucket_name"

        # Tag bucket
        aws s3api put-bucket-tagging --bucket "$bucket_name" \
            --tagging "TagSet=[{Key=Project,Value=$PROJECT_TAG}]"
        log "Tagged bucket: $bucket_name with Project=$PROJECT_TAG"

        # Enable versioning
        aws s3api put-bucket-versioning --bucket "$bucket_name" --versioning-configuration Status=Enabled
        log "Enabled versioning on bucket: $bucket_name"

        # Upload sample file
        if [[ ! -f "$SAMPLE_FILE" ]]; then
            echo "Welcome to Automation Lab!" > "$SAMPLE_FILE"
        fi
        aws s3 cp "$SAMPLE_FILE" "s3://$bucket_name/$SAMPLE_FILE"
        log "Uploaded sample file to bucket: $bucket_name"
    else
        log "Bucket already exists: $bucket_name"
    fi
}

main() {
    log "Starting S3 bucket automation script"

    check_prerequisites

    # Make a unique bucket name
    BUCKET_NAME="${BUCKET_PREFIX}-$(date +%s)"

    ensure_s3_bucket "$BUCKET_NAME"

    log "S3 bucket automation completed successfully"
    echo
    echo "Bucket Name: $BUCKET_NAME"
}

main
