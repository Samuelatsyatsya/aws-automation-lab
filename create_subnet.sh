#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="create_vpc_with_named_subnet.log"

# Configuration
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"
VPC_NAME="automationlab-vpc"
SUBNET_NAME="automationlab-public-subnet"

log() {
    local LEVEL="${2:-INFO}"
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$LEVEL] : $1" | tee -a "$LOG_FILE" >&2
}

error_exit() {
    log "$1" "ERROR"
    exit 1
}

check_prerequisites() {
    command -v aws >/dev/null 2>&1 || error_exit "AWS CLI not installed."
    aws sts get-caller-identity >/dev/null 2>&1 || error_exit "AWS credentials not configured or invalid."
}

# ---------------- GENERIC RESOURCE ENSURER ----------------
# Arguments:
# 1 = describe_command (command to get existing resource, output text)
# 2 = create_command (command to create resource if missing, output text)
# 3 = resource_name (for logging)
# Sets global variable with resource id

ensure_resource() {
    local describe_cmd="$1"
    local create_cmd="$2"
    local name="$3"

    RESOURCE_ID=$(eval "$describe_cmd")

    if [[ -z "$RESOURCE_ID" || "$RESOURCE_ID" == "None" ]]; then
        RESOURCE_ID=$(eval "$create_cmd")
        log "Created $name: $RESOURCE_ID"
    else
        log "$name already exists: $RESOURCE_ID"
    fi
}

# ---------------- MAIN ----------------

main() {
    log "Starting VPC and subnet setup"

    check_prerequisites
    REGION=$(aws configure get region)
    log "Using region: $REGION"

    # ---------------- VPC ----------------
    ensure_resource \
      "aws ec2 describe-vpcs --filters Name=tag:Name,Values=$VPC_NAME --query 'Vpcs[0].VpcId' --output text --region $REGION" \
      "aws ec2 create-vpc --cidr-block $VPC_CIDR --query 'Vpc.VpcId' --output text --region $REGION && \
       aws ec2 modify-vpc-attribute --vpc-id \$RESOURCE_ID --enable-dns-support --region $REGION && \
       aws ec2 modify-vpc-attribute --vpc-id \$RESOURCE_ID --enable-dns-hostnames --region $REGION && \
       aws ec2 create-tags --resources \$RESOURCE_ID --tags Key=Name,Value=$VPC_NAME --region $REGION" \
      "VPC"
    VPC_ID="$RESOURCE_ID"

    # ---------------- SUBNET ----------------
    AZ=$(aws ec2 describe-availability-zones --query "AvailabilityZones[0].ZoneName" --output text --region "$REGION")
    ensure_resource \
      "aws ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID Name=tag:Name,Values=$SUBNET_NAME --query 'Subnets[0].SubnetId' --output text --region $REGION" \
      "aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $SUBNET_CIDR --availability-zone $AZ --query 'Subnet.SubnetId' --output text --region $REGION && \
       aws ec2 modify-subnet-attribute --subnet-id \$RESOURCE_ID --map-public-ip-on-launch --region $REGION && \
       aws ec2 create-tags --resources \$RESOURCE_ID --tags Key=Name,Value=$SUBNET_NAME --region $REGION" \
      "Subnet"
    SUBNET_ID="$RESOURCE_ID"

    # ---------------- INTERNET GATEWAY ----------------
    ensure_resource \
      "aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$VPC_ID --query 'InternetGateways[0].InternetGatewayId' --output text --region $REGION" \
      "aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text --region $REGION && \
       aws ec2 attach-internet-gateway --internet-gateway-id \$RESOURCE_ID --vpc-id $VPC_ID --region $REGION" \
      "Internet Gateway"
    IGW_ID="$RESOURCE_ID"

    # ---------------- ROUTE TABLE ----------------
    ensure_resource \
      "aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID --query 'RouteTables[?Routes[?DestinationCidrBlock==\`0.0.0.0/0\`]].RouteTableId | [0]' --output text --region $REGION" \
      "aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text --region $REGION && \
       aws ec2 create-route --route-table-id \$RESOURCE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID --region $REGION && \
       aws ec2 associate-route-table --route-table-id \$RESOURCE_ID --subnet-id $SUBNET_ID --region $REGION" \
      "Route Table"
    RT_ID="$RESOURCE_ID"

    # ---------------- SUMMARY ----------------
    log "VPC and subnet setup completed successfully"
    echo
    echo "VPC Name   : $VPC_NAME"
    echo "VPC ID     : $VPC_ID"
    echo "Subnet Name: $SUBNET_NAME"
    echo "Subnet ID  : $SUBNET_ID"
    echo "Internet GW: $IGW_ID"
    echo "Route Table: $RT_ID"
}

main
