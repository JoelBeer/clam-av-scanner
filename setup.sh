#!/bin/bash
# Update system packages
yum update -y

# Update system & install required packages
sudo yum update -y
sudo yum install -y clamav clamav-update  aws-cli python3-pip

sudo freshclam

# Configure daily ClamAV database updates
echo "0 3 * * * root freshclam" | sudo tee -a /etc/crontab

# Set environment variables
echo 'export BUCKET_NAME="<bucket-name>"' >> /etc/environment
echo 'export AWS_REGION="<region>"' >> /etc/environment
echo 'export SQS_QUEUE_URL="https://sqs.eu-west-2.amazonaws.com/<account-id>/<queue-name>"' >> /etc/environment

# Load environment variables
source /etc/environment

# Clone the GitHub repo (public repo, no authentication needed)
git clone https://github.com/JoelBeer/clam-av-scanner.git /home/ec2-user/clamav-scanner

# Move to the script directory
cd /home/ec2-user/clamav-scanner

# Install Python dependencies
pip3 install boto3

# Ensure correct permissions
chmod +x scan_sqs.py

# Start the script in the background
nohup python3 scan_sqs.py > /home/ec2-user/clamav-scanner/clamav.log 2>&1 &
