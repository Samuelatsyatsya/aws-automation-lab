# #!/usr/bin/env bash
# set -euo pipefail

# # ---------------- CONFIGURATION ----------------
# LOG_DIR="./logs"
# mkdir -p "$LOG_DIR"
# LOG_FILE="$LOG_DIR/cleanup_resources.log"

# STATE_FILE="./state/state.json"
# : "${REGION:=$(aws configure get region)}"
# : "${PROJECT_TAG:=AutomationLab}"

# # ---------------- LOG FUNCTION ----------------
# log() {
#     local LEVEL="${2:-INFO}"
#     echo "$(date '+%Y-%m-%d %H:%M:%S') [$LEVEL] : $1" | tee -a "$LOG_FILE" >&2
# }

# error_exit() {
#     log "$1" "ERROR"
#     exit 1
# }

# check_prerequisites() {
#     command -v aws >/dev/null 2>&1 || error_exit "AWS CLI not installed."
#     command -v jq >/dev/null 2>&1 || error_exit "jq not installed."
#     aws sts get-caller-identity >/dev/null 2>&1 || error_exit "AWS credentials not configured or invalid."
# }

# # ---------------- GENERIC CLEANUP FUNCTION ----------------
# ensure_cleanup() {
#     local resource_type="$1"
#     local resource_ids
#     resource_ids=$(jq -r --arg type "$resource_type" '.[$type][]?' "$STATE_FILE" 2>/dev/null || true)

#     if [[ -z "$resource_ids" ]]; then
#         log "No $resource_type to clean."
#         return
#     fi

#     for RES in $resource_ids; do
#         case "$resource_type" in
#             ec2)
#                 log "Terminating EC2 instance: $RES"
#                 aws ec2 terminate-instances --instance-ids "$RES" --region "$REGION" >/dev/null || true
#                 aws ec2 wait instance-terminated --instance-ids "$RES" --region "$REGION" >/dev/null || true
#                 ;;
#             s3)
#                 log "Deleting all objects and bucket: $RES"
#                 # Delete objects and versions
#                 aws s3api list-object-versions --bucket "$RES" --output json | \
#                   jq -c '.Versions[]?, .DeleteMarkers[]?' | while read -r OBJ; do
#                     aws s3api delete-object --bucket "$RES" \
#                         --key "$(echo "$OBJ" | jq -r '.Key')" \
#                         --version-id "$(echo "$OBJ" | jq -r '.VersionId')" >/dev/null || true
#                   done
#                 # Delete bucket
#                 aws s3api delete-bucket --bucket "$RES" --region "$REGION" >/dev/null || true
#                 ;;
#             security_groups)
#                 log "Deleting security group: $RES"
#                 aws ec2 delete-security-group --group-id "$RES" --region "$REGION" >/dev/null || true
#                 ;;
#             subnets)
#                 log "Deleting subnet: $RES"
#                 aws ec2 delete-subnet --subnet-id "$RES" --region "$REGION" >/dev/null || true
#                 ;;
#             vpcs)
#                 log "Deleting VPC: $RES"
#                 aws ec2 delete-vpc --vpc-id "$RES" --region "$REGION" >/dev/null || true
#                 ;;
#             key_pairs)
#                 log "Deleting key pair: $RES"
#                 aws ec2 delete-key-pair --key-name "$RES" --region "$REGION" >/dev/null || true
#                 rm -f "${RES}.pem" 2>/dev/null || true
#                 ;;
#             *)
#                 log "Unknown resource type: $resource_type" "WARN"
#                 ;;
#         esac
#         # Remove resource from state
#         jq "del(.$resource_type[] | select(. == \"$RES\"))" "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"
#     done
# }

# # ---------------- MAIN ----------------
# log "Resource Cleanup Script Started"

# check_prerequisites

# if [[ ! -f "$STATE_FILE" ]]; then
#     log "No state file found at $STATE_FILE. Nothing to clean."
#     exit 0
# fi

# # List of resource types to cleanup in order (dependencies first)
# RESOURCE_TYPES=("ec2" "key_pairs" "s3" "security_groups" "subnets" "vpcs")

# for TYPE in "${RESOURCE_TYPES[@]}"; do
#     ensure_cleanup "$TYPE"
# done

# log "Resource Cleanup Script Completed Successfully"


#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="./logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/cleanup_resources.log"

STATE_FILE="./state/state.json"
: "${STATE_FILE:=${STATE_FILE:-./state/state.json}}"
if [[ ! -f "$STATE_FILE" ]]; then
    echo "{}" > "$STATE_FILE"
fi

# Load helpers
if [[ -f "./utils/aws_helper.sh" ]]; then
    source ./utils/aws_helper.sh
else
    echo "ERROR: aws_helper.sh not found"
    exit 1
fi

log "Resource Cleanup Script Started"
check_prerequisites
cleanup_all_resources
log "Resource Cleanup Script Completed Successfully"


