#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="./logs/create_s3.log"
check_prerequisites

# Make unique bucket name with timestamp
BUCKET_NAME="${BUCKET_PREFIX}-$(date +%s)"

# Ensure bucket exists
ensure_resource "S3 Bucket" "s3_bucket_id" \
    "aws s3api head-bucket --bucket $BUCKET_NAME >/dev/null 2>&1 && echo $BUCKET_NAME || echo ''" \
    "aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION --create-bucket-configuration LocationConstraint=$REGION && \
     aws s3api put-bucket-tagging --bucket \$RESOURCE_ID --tagging 'TagSet=[{Key=Project,Value=$PROJECT_TAG}]' && \
     aws s3api put-bucket-versioning --bucket \$RESOURCE_ID --versioning-configuration Status=Enabled"

log "S3 bucket automation completed"
echo "Bucket Name: $BUCKET_NAME"
