#!/usr/bin/env bash
set -e

#CONFIGURATION
source "./state/dev.env"

acquire_lock() {
  aws dynamodb put-item \
    --table-name "$LOCK_TABLE" \
    --item '{"LockID":{"S":"'"$LOCK_ID"'"}}' \
    --condition-expression "attribute_not_exists(LockID)"

  echo "Lock acquired"
}

release_lock() {
  aws dynamodb delete-item \
    --table-name "$LOCK_TABLE" \
    --key '{"LockID":{"S":"'"$LOCK_ID"'"}}'

  echo "Lock released"
}
