#!/usr/bin/env bash
set -euo pipefail

# CONFIG
: "${REGION:?REGION must be set (source env.sh)}"
: "${BUCKET_PREFIX:?BUCKET_PREFIX must be set}"
: "${ENV:?ENV must be set}"

LOG_FILE="./logs/create_s3.log"
STATE_FILE="./state/state.json"

mkdir -p ./logs ./state
[[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"

#SOURCE HELPERS
source ./utils/aws_helper.sh

# START
log "Starting STATE-BASED S3 bucket setup"

# Deterministic bucket name
BUCKET_NAME="${BUCKET_PREFIX}-${ENV}-${REGION}"

# S3 BUCKET
STATE_BUCKET=$(get_state "s3_bucket_name")

if [[ -z "$STATE_BUCKET" ]]; then
  log "Creating S3 bucket: $BUCKET_NAME"

  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"

  aws s3api put-bucket-tagging \
    --bucket "$BUCKET_NAME" \
    --tagging "TagSet=[{Key=Project,Value=${BUCKET_PREFIX}},{Key=Environment,Value=${ENV}}]"

  aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled

  set_state "s3_bucket_name" "$BUCKET_NAME"
  log "S3 bucket created and stored in state: $BUCKET_NAME"
else
  log "S3 bucket exists in state: $STATE_BUCKET"
fi

# DONE
log "STATE-BASED S3 bucket setup completed"

echo
echo "S3 Bucket Name : $(get_state s3_bucket_name)"
