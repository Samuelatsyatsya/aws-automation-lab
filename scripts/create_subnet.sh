#!/usr/bin/env bash
set -euo pipefail

# ---------------- CONFIG ----------------
REGION="${REGION:-us-east-1}"
VPC_NAME="${VPC_NAME:-automationlab-vpc}"
SUBNET_NAME="${SUBNET_NAME:-automationlab-public-subnet}"
RT_NAME="${RT_NAME:-automationlab-public-rt}"
VPC_CIDR="${VPC_CIDR:-10.0.0.0/16}"
SUBNET_CIDR="${SUBNET_CIDR:-10.0.1.0/24}"

LOG_FILE="./logs/create_subnet.log"
STATE_FILE="./state/state.json"

mkdir -p ./logs ./state
[[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"

# ---------------- LOGGING ----------------
log() {
  local msg="[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] : $*"
  echo "$msg"
  echo "$msg" >> "$LOG_FILE"
}

# ---------------- STATE HELPERS ----------------
get_state() {
  jq -r --arg k "$1" '.[$k] // empty' "$STATE_FILE"
}

set_state() {
  local tmp
  tmp=$(mktemp)
  jq --arg k "$1" --arg v "$2" '.[$k]=$v' "$STATE_FILE" > "$tmp"
  mv "$tmp" "$STATE_FILE"
}

# ---------------- START ----------------
log "Starting STATE-BASED VPC & Subnet setup"

# ---------------- VPC ----------------
VPC_ID=$(get_state "vpc_id")

if [[ -z "$VPC_ID" ]]; then
  log "Creating VPC"
  VPC_ID=$(aws ec2 create-vpc \
    --cidr-block "$VPC_CIDR" \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=$VPC_NAME}]" \
    --query 'Vpc.VpcId' \
    --output text \
    --region "$REGION")

  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-support --region "$REGION"
  aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames --region "$REGION"

  set_state "vpc_id" "$VPC_ID"
  log "VPC created: $VPC_ID"
else
  log "VPC exists in state: $VPC_ID"
fi

# ---------------- INTERNET GATEWAY ----------------
IGW_ID=$(get_state "igw_id")

if [[ -z "$IGW_ID" ]]; then
  log "Creating Internet Gateway"
  IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw}]" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text \
    --region "$REGION")

  aws ec2 attach-internet-gateway \
    --internet-gateway-id "$IGW_ID" \
    --vpc-id "$VPC_ID" \
    --region "$REGION"

  set_state "igw_id" "$IGW_ID"
  log "IGW created: $IGW_ID"
else
  log "IGW exists in state: $IGW_ID"
fi

# ---------------- SUBNET ----------------
SUBNET_ID=$(get_state "subnet_id")

if [[ -z "$SUBNET_ID" ]]; then
  log "Creating Subnet"
  SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$SUBNET_CIDR" \
    --availability-zone "${REGION}a" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=$SUBNET_NAME}]" \
    --query 'Subnet.SubnetId' \
    --output text \
    --region "$REGION")

  aws ec2 modify-subnet-attribute \
    --subnet-id "$SUBNET_ID" \
    --map-public-ip-on-launch \
    --region "$REGION"

  set_state "subnet_id" "$SUBNET_ID"
  log "Subnet created: $SUBNET_ID"
else
  log "Subnet exists in state: $SUBNET_ID"
fi

# ---------------- ROUTE TABLE ----------------
RT_ID=$(get_state "rt_id")

if [[ -z "$RT_ID" ]]; then
  log "Creating Route Table"
  RT_ID=$(aws ec2 create-route-table \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=$RT_NAME}]" \
    --query 'RouteTable.RouteTableId' \
    --output text \
    --region "$REGION")

  aws ec2 create-route \
    --route-table-id "$RT_ID" \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "$IGW_ID" \
    --region "$REGION"

  aws ec2 associate-route-table \
    --route-table-id "$RT_ID" \
    --subnet-id "$SUBNET_ID" \
    --region "$REGION"

  set_state "rt_id" "$RT_ID"
  log "Route Table created: $RT_ID"
else
  log "Route Table exists in state: $RT_ID"
fi

# ---------------- DONE ----------------
log "STATE-BASED VPC and Subnet setup completed"

echo
echo "VPC ID      : $VPC_ID"
echo "Subnet ID   : $SUBNET_ID"
echo "IGW ID      : $IGW_ID"
echo "Route Table : $RT_ID"
