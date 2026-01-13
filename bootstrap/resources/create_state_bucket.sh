#!/usr/bin/env bash
set -e

# Configuration
source "./bootstrap.env"

#Logging
source "./bootstrap_helper.sh"

# Create the S3 bucket
aws s3api create-bucket \
  --bucket "$STATE_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION" || {
    log "Bucket may already exist or an error occurred"
}

# Attach the bucket policy
aws s3api put-bucket-policy \
  --bucket "$STATE_BUCKET" \
  --policy file://"$POLICY_FILE"

# Enable versioning for recovery
aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

# Enable server-side encryption (AES256)
aws s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{
      "Rules": [
        {
          "ApplyServerSideEncryptionByDefault": {
            "SSEAlgorithm": "AES256"
          }
        }
      ]
    }'

log "State bucket bootstrap complete"
