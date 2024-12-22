#!/bin/bash

LOG_FILE=/var/log/promtail_deployment.log
CONFIG_DIR=/root/grafana_configs
PROMTAIL_IMAGE=grafana/promtail:2.9.1
PROMTAIL_CONTAINER=promtail
PROMTAIL_CONFIG_FILE=$CONFIG_DIR/promtail-config.yaml

echo "Starting Promtail Deployment" > $LOG_FILE

# Download updated configs from S3
echo "Downloading files from S3..." >> $LOG_FILE
aws s3 cp s3://promtail-deploy-bucket/ $CONFIG_DIR/ --recursive >> $LOG_FILE 2>&1

# Validate files
if [[ ! -f $CONFIG_DIR/generate_promtail_config.sh ]]; then
  echo "ERROR: Required files missing!" >> $LOG_FILE
  exit 1
fi

# Generate Promtail configuration
echo "Generating Promtail configuration..." >> $LOG_FILE
$CONFIG_DIR/generate_promtail_config.sh >> $LOG_FILE 2>&1

# Manage Docker container
echo "Stopping existing Promtail container..." >> $LOG_FILE
docker stop $PROMTAIL_CONTAINER >> $LOG_FILE 2>&1 || true
docker rm $PROMTAIL_CONTAINER >> $LOG_FILE 2>&1 || true

echo "Starting new Promtail container..." >> $LOG_FILE
docker run -d \
  --name=$PROMTAIL_CONTAINER \
  -v $PROMTAIL_CONFIG_FILE:/etc/promtail/config.yaml \
  -v /applog/log:/applog/log:ro \
  -v /var/log/nginx:/var/log/nginx:ro \
  -v /tmp/promtail-positions:/tmp/promtail-positions \
  -p 9080:9080 \
  $PROMTAIL_IMAGE \
  -config.file=/etc/promtail/config.yaml >> $LOG_FILE 2>&1

# Verify Promtail container
docker ps | grep $PROMTAIL_CONTAINER >> $LOG_FILE
if [[ $? -ne 0 ]]; then
  echo "ERROR: Promtail container failed to start!" >> $LOG_FILE
  exit 1
fi

echo "Deployment completed successfully." >> $LOG_FILE

