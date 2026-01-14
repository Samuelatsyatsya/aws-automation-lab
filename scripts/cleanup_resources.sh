#!/usr/bin/env bash
set -euo pipefail

# source helpers and config
source "./utils/aws_helper.sh"
source "./config/aws_env.sh"
source "./state/lock.sh"   # contains acquire_lock and release_lock functions

: "${REGION:?REGION must be set}"
: "${STATE_BUCKET:?STATE_BUCKET must be set}"
: "${STATE_KEY:=state.json}"
: "${STATE_FILE:=./state/state.json}"
: "${LOG_FILE:=./logs/cleanup.log}"

mkdir -p "$(dirname "$STATE_FILE")" "$(dirname "$LOG_FILE")"

# simple log function
log() {
    echo "[INFO] : $*" | tee -a "$LOG_FILE"
}

# get a value from state file
get_state() {
    jq -r --arg k "$1" '.[$k] // empty' "$STATE_FILE"
}

# delete a key from state file
delete_state_key() {
    jq "del(.$1)" "$STATE_FILE" > tmp.$$.json && mv tmp.$$.json "$STATE_FILE"
}

# delete a resource if it exists in state
delete_if_tracked() {
    local key="$1"
    local label="$2"
    local delete_cmd_template="$3"

    local resource_id
    resource_id=$(get_state "$key")

    if [[ -z "$resource_id" ]]; then
        log "No $label found in state"
        return
    fi

    log "Deleting $label: $resource_id"
    local delete_cmd="${delete_cmd_template//__ID__/$resource_id}"
    eval "$delete_cmd"
    delete_state_key "$key"
}

# cleanup resources based on state
cleanup_all_resources() {
    log "Starting cleanup using S3 state"

    delete_if_tracked \
        "ec2_instance_id" \
        "EC2 Instance" \
        "aws ec2 terminate-instances --instance-ids __ID__ --region $REGION && \
         aws ec2 wait instance-terminated --instance-ids __ID__ --region $REGION"

    delete_if_tracked \
        "security_group_id" \
        "Security Group" \
        "aws ec2 delete-security-group --group-id __ID__ --region $REGION"

    rt_id=$(get_state "rt_id")
    rt_assoc_id=$(get_state "rt_assoc_id")
    if [[ -n "$rt_id" ]]; then
        log "Deleting Route Table: $rt_id"
        if [[ -n "$rt_assoc_id" ]]; then
            aws ec2 disassociate-route-table --association-id "$rt_assoc_id" --region "$REGION"
            delete_state_key "rt_assoc_id"
        fi
        aws ec2 delete-route-table --route-table-id "$rt_id" --region "$REGION"
        delete_state_key "rt_id"
    else
        log "No Route Table found in state"
    fi

    delete_if_tracked \
        "subnet_id" \
        "Subnet" \
        "aws ec2 delete-subnet --subnet-id __ID__ --region $REGION"

    igw_id=$(get_state "igw_id")
    vpc_id=$(get_state "vpc_id")
    if [[ -n "$igw_id" ]]; then
        log "Deleting Internet Gateway: $igw_id"
        if [[ -n "$vpc_id" ]]; then
            aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" --region "$REGION"
        fi
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$REGION"
        delete_state_key "igw_id"
    else
        log "No Internet Gateway found in state"
    fi

    s3_bucket=$(get_state "s3_bucket_name")
    if [[ -n "$s3_bucket" ]]; then
        log "Deleting S3 Bucket: $s3_bucket"
        aws s3 rm "s3://$s3_bucket" --recursive
        aws s3 rb "s3://$s3_bucket"
        delete_state_key "s3_bucket_name"
    else
        log "No S3 bucket found in state"
    fi

    delete_if_tracked \
        "vpc_id" \
        "VPC" \
        "aws ec2 delete-vpc --vpc-id __ID__ --region $REGION"

    log "Resetting script execution state"
    jq 'del(
        ."create_subnet.sh",
        ."create_security_group.sh",
        ."create_s3_bucket.sh",
        ."create_ec2.sh"
    )' "$STATE_FILE" > tmp.$$.json && mv tmp.$$.json "$STATE_FILE"

    log "Cleanup completed successfully"
}

# trap to release lock on exit
trap release_lock EXIT

# acquire DynamoDB lock
log "Acquiring lock..."
acquire_lock

# download latest state from S3
log "Downloading state from S3..."
aws s3 cp "s3://$STATE_BUCKET/$STATE_KEY" "$STATE_FILE"

# run cleanup
cleanup_all_resources

# upload updated state back to S3
log "Uploading updated state to S3..."
aws s3 cp "$STATE_FILE" "s3://$STATE_BUCKET/$STATE_KEY"

# release lock
log "Releasing lock..."
release_lock
