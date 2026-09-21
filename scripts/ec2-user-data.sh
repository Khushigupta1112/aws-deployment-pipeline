#!/usr/bin/env bash
# EC2 user-data (cloud-init) for Amazon Linux 2023.
# Runs once on first boot as root and prepares the deployment host:
#   - Docker + docker start-on-boot
#   - ec2-user in the docker group (CI/SSH sessions can run docker without sudo)
#   - deployment working directories
# AWS CLI v2 is preinstalled on AL2023, so no AWS credential files are needed
# — the instance pulls images via its IAM instance role.
set -euo pipefail

dnf -y update
dnf -y install docker
systemctl enable --now docker
usermod -aG docker ec2-user

mkdir -p /home/ec2-user/app
chown -R ec2-user:ec2-user /home/ec2-user/app

touch /home/ec2-user/app/user-data-complete.txt
echo "[user-data] setup complete"
