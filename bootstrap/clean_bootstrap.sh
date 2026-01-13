
#!/usr/bin/env bash
set -euo pipefail

# Configuration
source "./bootstrap.env"

#Logging
source "./bootstrap_helper.sh"

read -p "This will delete S3 bucket and DynamoDB lock table. Are you sure? (yes/no): " confirm
[[ "$confirm" == "yes" ]] || exit 0


# Delete all versions from S3 bucket
log "Deleting all objects and versions from S3 bucket $STATE_BUCKET..."

aws s3api list-object-versions --bucket "$STATE_BUCKET" --output json |
jq -r '(.Versions // [])[] | [.Key, .VersionId] | @tsv' |
while read -r key version; do
    aws s3api delete-object \
        --bucket "$STATE_BUCKET" \
        --key "$key" \
        --version-id "$version"
done

aws s3api list-object-versions --bucket "$STATE_BUCKET" --output json |
jq -r '(.DeleteMarkers // [])[] | [.Key, .VersionId] | @tsv' |
while read -r key version; do
    aws s3api delete-object \
        --bucket "$STATE_BUCKET" \
        --key "$key" \
        --version-id "$version"
done


# Delete S3 bucket
log "Deleting S3 bucket $STATE_BUCKET..."
aws s3api delete-bucket --bucket "$STATE_BUCKET" --region "$AWS_REGION"

# Delete DynamoDB lock table
log "Deleting DynamoDB lock table $LOCK_TABLE..."
aws dynamodb delete-table --table-name "$LOCK_TABLE" --region "$AWS_REGION"

echo "Bootstrap cleanup completed"
