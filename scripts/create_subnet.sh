#!/usr/bin/env bash
set -euo pipefail

# ---------------- CONFIG ----------------
LOG_FILE="./logs/create_subnet.log"
STATE_FILE="./state/state.json"
mkdir -p ./logs ./state

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] : $*"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] : $*" >> "$LOG_FILE"
}

check_prerequisites() {
    command -v aws >/dev/null 2>&1 || { echo "aws CLI not found"; exit 1; }
    command -v jq >/dev/null 2>&1 || { echo "jq not found"; exit 1; }
}

save_state() {
    local key="$1"
    local value="$2"
    tmp=$(mktemp)
    jq --arg k "$key" --arg v "$value" '.[$k]=$v' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# ---------------- START ----------------
log "Starting VPC and Subnet setup"
check_prerequisites

REGION="${REGION:-us-east-1}"
VPC_NAME="${VPC_NAME:-automationlab-vpc}"
SUBNET_NAME="${SUBNET_NAME:-automationlab-public-subnet}"
VPC_CIDR="${VPC_CIDR:-10.0.0.0/16}"
SUBNET_CIDR="${SUBNET_CIDR:-10.0.1.0/24}"

# ---------------- VPC ----------------
VPC_ID=$(aws ec2 describe-vpcs \
    --filters Name=tag:Name,Values="$VPC_NAME" \
    --query 'Vpcs[0].VpcId' --output text --region "$REGION")

if [[ "$VPC_ID" == "None" ]]; then
    log "Creating VPC: $VPC_NAME"
    VPC_ID=$(aws ec2 create-vpc --cidr-block "$VPC_CIDR" --query 'Vpc.VpcId' --output text --region "$REGION")
    aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support --region "$REGION"
    aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames --region "$REGION"
    aws ec2 create-tags --resources "$VPC_ID" --tags Key=Name,Value="$VPC_NAME" --region "$REGION"
    log "Created VPC: $VPC_ID"
else
    log "VPC exists in AWS: $VPC_ID"
fi
save_state "vpc_id" "$VPC_ID"

# ---------------- SUBNET ----------------
AZ=$(aws ec2 describe-availability-zones --query "AvailabilityZones[0].ZoneName" --output text --region "$REGION")

SUBNET_ID=$(aws ec2 describe-subnets \
    --filters Name=vpc-id,Values="$VPC_ID" Name=tag:Name,Values="$SUBNET_NAME" \
    --query 'Subnets[0].SubnetId' --output text --region "$REGION")

if [[ "$SUBNET_ID" == "None" ]]; then
    log "Creating Subnet: $SUBNET_NAME"
    SUBNET_ID=$(aws ec2 create-subnet \
        --vpc-id "$VPC_ID" \
        --cidr-block "$SUBNET_CIDR" \
        --availability-zone "$AZ" \
        --query 'Subnet.SubnetId' --output text --region "$REGION")
    aws ec2 modify-subnet-attribute --subnet-id "$SUBNET_ID" --map-public-ip-on-launch --region "$REGION"
    aws ec2 create-tags --resources "$SUBNET_ID" --tags Key=Name,Value="$SUBNET_NAME" --region "$REGION"
    log "Created Subnet: $SUBNET_ID"
else
    log "Subnet exists in AWS: $SUBNET_ID"
fi
save_state "subnet_id" "$SUBNET_ID"

# ---------------- INTERNET GATEWAY ----------------
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters Name=attachment.vpc-id,Values="$VPC_ID" \
    --query 'InternetGateways[0].InternetGatewayId' --output text --region "$REGION")

if [[ "$IGW_ID" == "None" ]]; then
    log "Creating Internet Gateway"
    IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text --region "$REGION")
    aws ec2 attach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" --region "$REGION"
    log "Created Internet Gateway: $IGW_ID"
else
    log "Internet Gateway exists in AWS: $IGW_ID"
fi
save_state "igw_id" "$IGW_ID"

# ---------------- ROUTE TABLE ----------------
RT_ID=$(aws ec2 describe-route-tables \
    --filters Name=vpc-id,Values="$VPC_ID" \
    --query 'RouteTables[?Routes[?DestinationCidrBlock==`0.0.0.0/0`]].RouteTableId | [0]' \
    --output text --region "$REGION")

if [[ "$RT_ID" == "None" ]]; then
    log "Creating Route Table"
    RT_ID=$(aws ec2 create-route-table --vpc-id "$VPC_ID" --query 'RouteTable.RouteTableId' --output text --region "$REGION")
    aws ec2 create-route --route-table-id "$RT_ID" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region "$REGION"
    aws ec2 associate-route-table --route-table-id "$RT_ID" --subnet-id "$SUBNET_ID" --region "$REGION"
    log "Created Route Table: $RT_ID"
else
    log "Route Table exists in AWS: $RT_ID"
fi
save_state "rt_id" "$RT_ID"

# ---------------- INFO ----------------
log "VPC and Subnet setup completed"
echo
echo "VPC Name   : $VPC_NAME"
echo "VPC ID     : $VPC_ID"
echo "Subnet Name: $SUBNET_NAME"
echo "Subnet ID  : $SUBNET_ID"
echo "IGW ID     : $IGW_ID"
echo "Route Table: $RT_ID"
