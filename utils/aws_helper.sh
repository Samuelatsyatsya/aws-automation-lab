#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------
# AWS Helpers: logging, prerequisites, unified ensures
# ---------------------------------------------

# ---------------- CONFIGURATION ----------------
LOG_FILE="${LOG_FILE:-./logs/aws_helper.log}"
STATE_FILE="${STATE_FILE:-./state.json}"
REGION="${REGION:-$(aws configure get region)}"
PROJECT_TAG="${PROJECT_TAG:-AutomationLab}"

mkdir -p "$(dirname "$LOG_FILE")"

# Ensure state file exists
if [[ ! -f "$STATE_FILE" ]]; then
    echo "{}" > "$STATE_FILE"
fi

# ---------------- LOGGING ----------------
log() {
    local LEVEL="${2:-INFO}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$LEVEL] : $1" | tee -a "$LOG_FILE" >&2
}

error_exit() {
    log "$1" "ERROR"
    exit 1
}

# ---------------- PREREQUISITES ----------------
check_prerequisites() {
    command -v aws >/dev/null 2>&1 || { log "Installing AWS CLI..."; sudo apt-get update && sudo apt-get install -y awscli; }
    command -v jq >/dev/null 2>&1 || { log "Installing jq..."; sudo apt-get update && sudo apt-get install -y jq; }
    aws sts get-caller-identity >/dev/null 2>&1 || error_exit "AWS credentials not configured or invalid."
}

# ---------------- STATE FILE HANDLING ----------------
load_state() {
    STATE=$(cat "$STATE_FILE")
}

save_state() {
    echo "$STATE" | jq '.' > "$STATE_FILE"
}

mark_done() {
    local key="$1"
    local value="$2"
    jq --arg k "$key" --arg v "$value" '.[$k]=$v' "$STATE_FILE" > tmp.$$.json && mv tmp.$$.json "$STATE_FILE"
}

is_done() {
    local key="$1"
    local exists
    exists=$(jq -r --arg k "$key" 'has($k) and .[$k] != null' "$STATE_FILE")
    [[ "$exists" == "true" ]]
}

get_resource() {
    local key="$1"
    jq -r --arg k "$key" '.[$k] // empty' "$STATE_FILE"
}

# ---------------- GENERIC ENSURE FUNCTION ----------------
ensure_resource() {
    local type="$1"
    local key="$2"
    local describe_cmd="$3"
    local create_cmd="$4"

    load_state

    local resource_id
    resource_id=$(get_resource "$key")

    if [[ -n "$resource_id" ]]; then
        log "$type already tracked in state: $resource_id"
        echo "$resource_id"
        return
    fi

    resource_id=$(eval "$describe_cmd")
    if [[ -n "$resource_id" && "$resource_id" != "None" ]]; then
        log "$type exists in AWS: $resource_id"
    else
        log "Creating $type..."
        resource_id=$(eval "$create_cmd")
        log "Created $type: $resource_id"
    fi

    mark_done "$key" "$resource_id"
    echo "$resource_id"
}
# ---------------- CLEANUP FUNCTIONS ----------------
cleanup_all_resources() {
    log "Cleaning all resources created by AutomationLab..."

    # EC2
    local ec2_id
    ec2_id=$(get_resource "ec2_instance_id")
    if [[ -n "$ec2_id" ]]; then
        log "Terminating EC2 instance: $ec2_id"
        aws ec2 terminate-instances --instance-ids "$ec2_id" --region "$REGION"
        aws ec2 wait instance-terminated --instance-ids "$ec2_id" --region "$REGION"
        jq "del(.ec2_instance_id)" "$STATE_FILE" > tmp.$$.json && mv tmp.$$.json "$STATE_FILE"
    else
        log "No EC2 instance to clean."
    fi

    # S3
  # S3
# local bucket
# bucket=$(get_resource "s3_bucket_id")
# if [[ -n "$bucket" && "$bucket" != "null" ]]; then
#     # Make sure bucket is a plain string
#     bucket=$(echo "$bucket" | jq -r '.')
#     log "Deleting S3 bucket: $bucket"
#     aws s3 rb "s3://$bucket" --force
#     jq 'del(.s3_bucket_id)' "$STATE_FILE" > tmp.$$.json && mv tmp.$$.json "$STATE_FILE"
# else
#     log "No S3 bucket to clean."
# fi

# bucket=$(get_resource "s3_bucket_id" | jq -r '. // empty')
# if [[ -n "$bucket" ]]; then
#     log "Deleting S3 bucket: $bucket"
#     aws s3 rb "s3://$bucket" --force
#     jq 'del(.s3_bucket_id)' "$STATE_FILE" > tmp.$$.json && mv tmp.$$.json "$STATE_FILE"
# else
#     log "No S3 bucket to clean."
# fi


    # Security Group
    local sg_id
    sg_id=$(get_resource "security_group_id")
    if [[ -n "$sg_id" ]]; then
        log "Deleting Security Group: $sg_id"
        aws ec2 delete-security-group --group-id "$sg_id" --region "$REGION"
        jq "del(.security_group_id)" "$STATE_FILE" > tmp.$$.json && mv tmp.$$.json "$STATE_FILE"
    else
        log "No Security Group to clean."
    fi

    # Subnet
    local subnet_id
    subnet_id=$(get_resource "subnet_id")
    if [[ -n "$subnet_id" ]]; then
        log "Deleting Subnet: $subnet_id"
        aws ec2 delete-subnet --subnet-id "$subnet_id" --region "$REGION"
        jq "del(.subnet_id)" "$STATE_FILE" > tmp.$$.json && mv tmp.$$.json "$STATE_FILE"
    else
        log "No Subnet to clean."
    fi

    # Internet Gateway
    local igw_id
    igw_id=$(get_resource "igw_id")
    if [[ -n "$igw_id" ]]; then
        log "Detaching and deleting Internet Gateway: $igw_id"
        local vpc_id
        vpc_id=$(get_resource "vpc_id")
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw_id" --vpc-id "$vpc_id" --region "$REGION"
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw_id" --region "$REGION"
        jq "del(.igw_id)" "$STATE_FILE" > tmp.$$.json && mv tmp.$$.json "$STATE_FILE"
    else
        log "No Internet Gateway to clean."
    fi

    # Route Table
    local rt_id
    rt_id=$(get_resource "rt_id")
    if [[ -n "$rt_id" ]]; then
        log "Deleting Route Table: $rt_id"
        aws ec2 delete-route-table --route-table-id "$rt_id" --region "$REGION"
        jq "del(.rt_id)" "$STATE_FILE" > tmp.$$.json && mv tmp.$$.json "$STATE_FILE"
    else
        log "No Route Table to clean."
    fi

    # VPC
    local vpc_id
    vpc_id=$(get_resource "vpc_id")
    if [[ -n "$vpc_id" ]]; then
        log "Deleting VPC: $vpc_id"
        aws ec2 delete-vpc --vpc-id "$vpc_id" --region "$REGION"
        jq "del(.vpc_id)" "$STATE_FILE" > tmp.$$.json && mv tmp.$$.json "$STATE_FILE"
    else
        log "No VPC to clean."
    fi

    log "All resources cleaned successfully."
}
