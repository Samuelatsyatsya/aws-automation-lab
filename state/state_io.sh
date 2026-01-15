#!/usr/bin/env bash
set -e

#CONFIGURATION
source "./state/dev.env"

download_state() {
  aws s3 cp \
    "s3://$STATE_BUCKET/$STATE_KEY" \
    "$STATE_FILE" \
    || echo "{}" > "$STATE_FILE"

  echo "State downloaded"
}

upload_state() {
  aws s3 cp \
    "$STATE_FILE" \
    "s3://$STATE_BUCKET/$STATE_KEY"

  echo "State uploaded"
}
