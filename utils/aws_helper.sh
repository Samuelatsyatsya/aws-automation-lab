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

# ---------------- ENSURE FUNCTIONS ----------------
ensure_vpc() {
    local vpc_name="${1:-automationlab-vpc}"
    local vpc_cidr="${2:-10.0.0.0/16}"

    ensure_resource "VPC" "vpc_id" \
        "aws ec2 describe-vpcs --filters Name=tag:Name,Values=$vpc_name --query 'Vpcs[0].VpcId' --output text --region $REGION" \
        "aws ec2 create-vpc --cidr-block $vpc_cidr --query 'Vpc.VpcId' --output text --region $REGION && \
         aws ec2 modify-vpc-attribute --vpc-id \$RESOURCE_ID --enable-dns-support --region $REGION && \
         aws ec2 modify-vpc-attribute --vpc-id \$RESOURCE_ID --enable-dns-hostnames --region $REGION && \
         aws ec2 create-tags --resources \$RESOURCE_ID --tags Key=Name,Value=$vpc_name --region $REGION && \
         echo \$RESOURCE_ID"
}

ensure_subnet() {
    local vpc_id="$1"
    local subnet_name="${2:-automationlab-public-subnet}"
    local subnet_cidr="${3:-10.0.1.0/24}"

    local az
    az=$(aws ec2 describe-availability-zones --query "AvailabilityZones[0].ZoneName" --output text --region "$REGION")

    ensure_resource "Subnet" "subnet_id" \
        "aws ec2 describe-subnets --filters Name=vpc-id,Values=$vpc_id Name=tag:Name,Values=$subnet_name --query 'Subnets[0].SubnetId' --output text --region $REGION" \
        "aws ec2 create-subnet --vpc-id $vpc_id --cidr-block $subnet_cidr --availability-zone $az --query 'Subnet.SubnetId' --output text --region $REGION && \
         aws ec2 modify-subnet-attribute --subnet-id \$RESOURCE_ID --map-public-ip-on-launch --region $REGION && \
         aws ec2 create-tags --resources \$RESOURCE_ID --tags Key=Name,Value=$subnet_name --region $REGION && \
         echo \$RESOURCE_ID"
}

ensure_internet_gateway() {
    local vpc_id="$1"
    ensure_resource "Internet Gateway" "igw_id" \
        "aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$vpc_id --query 'InternetGateways[0].InternetGatewayId' --output text --region $REGION" \
        "aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text --region $REGION && \
         aws ec2 attach-internet-gateway --internet-gateway-id \$RESOURCE_ID --vpc-id $vpc_id --region $REGION && \
         echo \$RESOURCE_ID"
}

ensure_route_table() {
    local vpc_id="$1"
    local subnet_id="$2"
    local igw_id="$3"

    ensure_resource "Route Table" "rt_id" \
        "aws ec2 describe-route-tables --filters Name=vpc-id,Values=$vpc_id --query 'RouteTables[?Routes[?DestinationCidrBlock==\`0.0.0.0/0\`]].RouteTableId | [0]' --output text --region $REGION" \
        "aws ec2 create-route-table --vpc-id $vpc_id --query 'RouteTable.RouteTableId' --output text --region $REGION && \
         aws ec2 create-route --route-table-id \$RESOURCE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $igw_id --region $REGION && \
         aws ec2 associate-route-table --route-table-id \$RESOURCE_ID --subnet-id $subnet_id --region $REGION && \
         echo \$RESOURCE_ID"
}

ensure_security_group() {
    local sg_name="${1:-automationlab-sg}"
    local description="${2:-Security group for AutomationLab EC2 instances}"

    ensure_resource "Security Group" "security_group_id" \
        "aws ec2 describe-security-groups --filters Name=group-name,Values=$sg_name Name=tag:Project,Values=$PROJECT_TAG --query 'SecurityGroups[0].GroupId' --output text --region $REGION" \
        "aws ec2 create-security-group --group-name $sg_name --description '$description' --region $REGION --query 'GroupId' --output text && \
         aws ec2 create-tags --resources \$RESOURCE_ID --tags Key=Project,Value=$PROJECT_TAG --region $REGION && \
         aws ec2 authorize-security-group-ingress --group-id \$RESOURCE_ID --protocol tcp --port 22 --cidr 0.0.0.0/0 --region $REGION && \
         aws ec2 authorize-security-group-ingress --group-id \$RESOURCE_ID --protocol tcp --port 80 --cidr 0.0.0.0/0 --region $REGION && \
         echo \$RESOURCE_ID"
}

ensure_s3_bucket() {
    local bucket_name="${1:-automationlab-bucket-$(date +%s)}"

    ensure_resource "S3 Bucket" "$bucket_name" \
        "aws s3api head-bucket --bucket $bucket_name 2>/dev/null || echo ''" \
        "aws s3api create-bucket --bucket $bucket_name --region $REGION --create-bucket-configuration LocationConstraint=$REGION && \
         aws s3api put-bucket-tagging --bucket $bucket_name --tagging 'TagSet=[{Key=Project,Value=$PROJECT_TAG}]' && \
         aws s3api put-bucket-versioning --bucket $bucket_name --versioning-configuration Status=Enabled && \
         echo $bucket_name"
}

ensure_ec2_instance() {
    local ami_id="$1"
    local key_name="$2"
    local instance_type="${3:-t3.micro}"
    local subnet_id="$4"

    ensure_resource "EC2 Instance" "ec2_instance_id" \
        "get_resource ec2_instance_id" \
        "aws ec2 run-instances --image-id $ami_id --instance-type $instance_type --key-name $key_name --subnet-id $subnet_id --count 1 --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=$PROJECT_TAG}]' --query 'Instances[0].InstanceId' --output text"
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
