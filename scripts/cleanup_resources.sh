#!/usr/bin/env bash
set -euo pipefail

# CONFIG (expects env.sh to be sourced)

: "${REGION:?REGION must be set}"
STATE_FILE="${STATE_FILE:-./state/state.json}"
LOG_FILE="${LOG_FILE:-./logs/cleanup.log}"

mkdir -p "$(dirname "$STATE_FILE")" "$(dirname "$LOG_FILE")"
[[ -f "$STATE_FILE" ]] || { echo "{}" > "$STATE_FILE"; }


#SOURCE HELPERS
source ./utils/aws_helper.sh

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


# CLEANUP (relying on STATE ONLY)
cleanup_all_resources() {
    log "Starting STATE-ONLY cleanup"

    # EC2
    delete_if_tracked \
        "ec2_instance_id" \
        "EC2 Instance" \
        "aws ec2 terminate-instances --instance-ids __ID__ --region $REGION && \
         aws ec2 wait instance-terminated --instance-ids __ID__ --region $REGION"

    # SECURITY GROUP
    delete_if_tracked \
        "security_group_id" \
        "Security Group" \
        "aws ec2 delete-security-group --group-id __ID__ --region $REGION"

    # ROUTE TABLE
    rt_id=$(get_state "rt_id")
    rt_assoc_id=$(get_state "rt_assoc_id")

    if [[ -n "$rt_id" ]]; then
        log "Deleting Route Table: $rt_id"

        if [[ -n "$rt_assoc_id" ]]; then
            aws ec2 disassociate-route-table \
                --association-id "$rt_assoc_id" \
                --region "$REGION"
            delete_state_key "rt_assoc_id"
        fi

        aws ec2 delete-route-table \
            --route-table-id "$rt_id" \
            --region "$REGION"

        delete_state_key "rt_id"
    else
        log "No Route Table found in state"
    fi

    # SUBNET
    delete_if_tracked \
        "subnet_id" \
        "Subnet" \
        "aws ec2 delete-subnet --subnet-id __ID__ --region $REGION"

    # INTERNET GATEWAY
    igw_id=$(get_state "igw_id")
    vpc_id=$(get_state "vpc_id")

    if [[ -n "$igw_id" ]]; then
        log "Deleting Internet Gateway: $igw_id"

        if [[ -n "$vpc_id" ]]; then
            aws ec2 detach-internet-gateway \
                --internet-gateway-id "$igw_id" \
                --vpc-id "$vpc_id" \
                --region "$REGION"
        fi

        aws ec2 delete-internet-gateway \
            --internet-gateway-id "$igw_id" \
            --region "$REGION"

        delete_state_key "igw_id"
    else
        log "No Internet Gateway found in state"
    fi

    # S3 BUCKET
    s3_bucket=$(get_state "s3_bucket_name")

    if [[ -n "$s3_bucket" ]]; then
        log "Deleting S3 Bucket: $s3_bucket"

        aws s3 rm "s3://$s3_bucket" --recursive
        aws s3 rb "s3://$s3_bucket"

        delete_state_key "s3_bucket_name"
    else
        log "No S3 bucket found in state"
    fi

    # VPC
    delete_if_tracked \
        "vpc_id" \
        "VPC" \
        "aws ec2 delete-vpc --vpc-id __ID__ --region $REGION"

    log "STATE-ONLY cleanup completed successfully"
}

# EXECUTE
cleanup_all_resources
