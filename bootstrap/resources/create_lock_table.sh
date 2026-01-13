#!/usr/bin/env bash
set -e

# Configuration
source "./bootstrap.env"

#Logging
source "./bootstrap_helper.sh"

# Create the DynamoDB table
aws dynamodb create-table \
  --table-name "$LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION" || {
    log "Table may already exist or an error occurred"
}

log "DynamoDB lock table $LOCK_TABLE created successfully"
