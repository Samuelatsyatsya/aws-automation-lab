#!/usr/bin/env bash
set -euo pipefail

# CONFIGURATION

LOG_FILE="create_s3_bucket.log"
REGION="eu-central-1"
BUCKET_NAME="automationlab-bucket-$(date +%s)"
TAG_PROJECT="AutomationLab"
SAMPLE_FILE="welcome.txt"

# LOGGING FUNCTION

log() {
  # Logs messages with timestamp to terminal and log file (stderr-safe)
  echo "$(date '+%Y-%m-%d %H:%M:%S') : $1" | tee -a "$LOG_FILE" >&2
}


# PREREQUISITES CHECK

check_prerequisites() {
  # Ensure AWS CLI is installed
  if ! command -v aws >/dev/null 2>&1; then
    log "ERROR: AWS CLI not installed."
    exit 1
  fi

  # Ensure AWS credentials are valid
  if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log "ERROR: AWS credentials not configured or invalid."
    exit 1
  fi

  log "AWS CLI and credentials verified."
}


# S3 FUNCTIONS
create_bucket() {
  log "Creating S3 bucket: $BUCKET_NAME"

  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"

  log "S3 bucket created successfully."
}

enable_versioning() {
  log "Enabling versioning on bucket: $BUCKET_NAME"

  aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled
}

upload_sample_file() {
  log "Uploading sample file to bucket."

  echo "Welcome to the AutomationLab S3 bucket!" > "$SAMPLE_FILE"

  aws s3 cp "$SAMPLE_FILE" "s3://$BUCKET_NAME/$SAMPLE_FILE"

  log "Sample file uploaded: s3://$BUCKET_NAME/$SAMPLE_FILE"
}

tag_bucket() {
  log "Tagging S3 bucket."

  aws s3api put-bucket-tagging \
    --bucket "$BUCKET_NAME" \
    --tagging "TagSet=[{Key=Project,Value=$TAG_PROJECT}]"
}

# MAIN EXECUTION

log "S3 Automation Script Started"

check_prerequisites
create_bucket
enable_versioning
tag_bucket
upload_sample_file

log "S3 Automation Script Completed"
log "Bucket Name: $BUCKET_NAME"
