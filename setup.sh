#!/bin/bash
# =====================================
# EC2 User Data Setup Script for ClamAV
# =====================================

# 1. Update system packages
yum update -y

# 2. Install required packages
sudo yum install -y clamav clamav-update clamd git aws-cli python3-pip cronie

# 3. Ensure cron (cronie) is running
sudo systemctl enable crond
sudo systemctl start crond

# 4. Install Supervisor using pip3 (since it's not available in yum repos)
sudo pip3 install supervisor

# 5. Generate a base Supervisor configuration file
echo_supervisord_conf | sudo tee /etc/supervisord.conf

# 6. Append ClamAV (clamd) configuration to Supervisor config.
#    This will start clamd in the foreground as the clamscan user.
sudo tee -a /etc/supervisord.conf << 'EOF'

[program:clamd]
command=/usr/sbin/clamd --foreground=yes --config-file=/etc/clamd.d/scan.conf
autostart=true
autorestart=true
user=clamscan
stderr_logfile=/var/log/clamd.err.log
stdout_logfile=/var/log/clamd.out.log
EOF

# 7. Create the socket directory and set proper ownership
sudo mkdir -p /run/clamd.scan
sudo chown clamscan:clamscan /run/clamd.scan
sudo chmod 775 /run/clamd.scan

# 8. Ensure /etc/clamd.d/scan.conf has the correct socket settings:
#    Uncomment the LocalSocket and FixStaleSocket lines if they are commented out.
sudo sed -i 's/^#\s*LocalSocket/LocalSocket/' /etc/clamd.d/scan.conf
sudo sed -i 's/^#\s*FixStaleSocket/FixStaleSocket/' /etc/clamd.d/scan.conf

# 9. Set correct permissions for the entire ClamAV database directory
sudo chown -R clamscan:clamscan /var/lib/clamav
sudo chmod -R 775 /var/lib/clamav

# 10. Ensure Freshclam log file exists and is writable by clamscan.
sudo touch /var/log/freshclam.log
sudo chown clamscan:clamscan /var/log/freshclam.log
sudo chmod 644 /var/log/freshclam.log

# 11. Ensure /etc/freshclam.conf is readable by clamscan.
sudo chown root:clamscan /etc/freshclam.conf
sudo chmod 640 /etc/freshclam.conf

# 12. Run an initial Freshclam update as clamscan to download the virus database files.
sudo -u clamscan freshclam

# 13. Add a cron job for nightly Freshclam updates at 3 AM.
(crontab -l 2>/dev/null; echo "0 3 * * * sudo -u clamscan freshclam >> /var/log/freshclam.log 2>&1") | crontab -

# 14. Start Supervisor (which will launch clamd as configured).
sudo /usr/local/bin/supervisord -c /etc/supervisord.conf

# 15. Add a cron job to start Supervisor on reboot.
(crontab -l 2>/dev/null; echo "@reboot /usr/local/bin/supervisord -c /etc/supervisord.conf") | crontab -

# 16. Clone the GitHub repository for your scan script.
git clone https://github.com/JoelBeer/clam-av-scanner.git /home/ec2-user/clamav-scanner

# 17. Set environment variables (AWS region, SQS URL).
echo 'AWS_REGION="<<aws-region>>"' | sudo tee -a /etc/environment
echo 'SQS_QUEUE_URL="<<sqs-queue-url>>"' | sudo tee -a /etc/environment

# 18. Change to the scan script directory and install Python dependencies.
cd /home/ec2-user/clamav-scanner
pip3 install boto3

# 19. Ensure the scan script is executable.
chmod +x scan_sqs.py

# 20. Start the scan script in the background using nohup.
nohup env AWS_REGION="<<aws-region>>" SQS_QUEUE_URL="<<sqs-queue-url>>" python3 /home/ec2-user/clamav-scanner/scan_sqs.py > /home/ec2-user/clamav-scanner/clamav.log 2>&1 &

# 21. Add a cron job to restart the scan script on reboot.
(crontab -l 2>/dev/null; echo '@reboot env AWS_REGION="<<aws-region>>" SQS_QUEUE_URL="<<sqs-queue-url>>" /usr/bin/nohup python3 /home/ec2-user/clamav-scanner/scan_sqs.py > /home/ec2-user/clamav-scanner/clamav.log 2>&1 &') | crontab -
