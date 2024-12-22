#!/bin/bash
echo "Pre-Install Hook: Updating system and installing Docker..."
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker
echo "Pre-Install Hook Completed"
