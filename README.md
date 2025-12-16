# AWS Resource Automation Project

## Project Overview

This project provides Bash scripts to automate AWS resource creation and management using the AWS CLI. The scripts help create EC2 instances, Security Groups, S3 buckets, and also clean up all resources after use.  

Automation ensures **consistency, efficiency, and security best practices** for provisioning cloud environments.

---

## Purpose of Each Script

### 1. `create_security_group.sh`
- Creates a Security Group named `automationlab-sg`  
- Opens ports **22 (SSH)** and **80 (HTTP)**  
- Outputs Security Group ID and rules  

### 2. `create_s3_bucket.sh`
- Creates a uniquely named S3 bucket  
- Enables versioning and uploads a sample file (`welcome.txt`)  
- Sets a simple bucket policy  

### 3. `create_ec2.sh`
- Creates an EC2 key pair (`automationlab-key-<timestamp>`)  
- Launches a free-tier Amazon Linux 2 EC2 instance  
- Tags the instance with `Project=AutomationLab`  
- Outputs the **Instance ID** and **Public IP**  

### 4. `run_all.sh`
- Orchestrates all creation scripts sequentially  
- Automatically sets execution permission if missing  
- Logs actions to `run_all.log`  

### 5. `cleanup_resources.sh`
- Deletes all resources created by the above scripts:  
  - EC2 instances  
  - EC2 key pairs and local `.pem` files  
  - S3 buckets (including all versions)  
  - Security groups  
- Logs actions to `cleanup_resources.log`  

---

## Setup and Execution

1. **Clone the repository**:
```bash
git clone <repository_url>
cd Resource_Creation
Ensure prerequisites:

AWS CLI v2 installed and configured

jq installed (sudo apt-get install -y jq)

Bash shell

Make scripts executable (optional):

bash
Copy code
chmod +x *.sh
Run all scripts in order:

bash
Copy code
./run_all.sh
Clean up resources:

bash
Copy code
./cleanup_resources.sh
Challenges Faced and Solutions
EC2 Instance ID parsing issue

Problem: Previous scripts were including log messages in the Instance ID

Solution: Separated the run-instances output using --query 'Instances[0].InstanceId' --output text

S3 bucket deletion failure

Problem: Versioned S3 buckets caused BucketNotEmpty errors

Solution: Implemented deletion of all object versions and delete markers using jq

Script execution permissions

Problem: Newly created scripts were not executable

Solution: run_all.sh automatically checks and sets executable permissions

AWS credential validation

Problem: Scripts failed when AWS credentials were missing or invalid

Solution: Added a check_prerequisites function in each script

Logging
Scripts log messages with timestamps to both terminal and log files:

create_ec2.log, create_s3_bucket.log, create_security_group.log, cleanup_resources.log, run_all.log

Author
Samuel Atsyatsya