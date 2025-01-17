#!/bin/bash

# Directories and Files
CONFIG_DIR="/root/grafana_configs"
OUTPUT_CONFIG="$CONFIG_DIR/promtail-config.yaml"
DOMAIN_BLACKLIST="$CONFIG_DIR/domain_blacklist.txt"
MARKETPLACEID_BLACKLIST="$CONFIG_DIR/marketplaceid_blacklist.txt"

# Backup Existing Configuration
if [[ -f "$OUTPUT_CONFIG" ]]; then
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  BACKUP_FILE="${OUTPUT_CONFIG}_${TIMESTAMP}.bak"
  cp "$OUTPUT_CONFIG" "$BACKUP_FILE"
  echo "Backup of existing Promtail configuration created: $BACKUP_FILE"
fi

# Server-Specific Variables
SERVER_NAME=$(hostname)
SERVER_IP=$(hostname -I | awk '{print $1}')
SERVER_FQDN=$(hostname -f)

# Dynamically Match Log File Names
ACCESS_LOG="/var/log/nginx/access.log"
DEBUG_LOG="/applog/log/debug-*.log"
REQUEST_LOG="/applog/log/requestlog-*.log"

# Check if Log Files Exist
if [[ ! -f "$ACCESS_LOG" ]]; then
  echo "ERROR: Access log file not found at $ACCESS_LOG. Exiting."
  exit 1
fi

if [[ -z $(ls $DEBUG_LOG 2>/dev/null) ]]; then
  echo "ERROR: No debug log files found matching pattern $DEBUG_LOG. Exiting."
  exit 1
else
  echo "Debug log files found: $(ls $DEBUG_LOG)"
fi

if [[ -z $(ls $REQUEST_LOG 2>/dev/null) ]]; then
  echo "ERROR: No request log files found matching pattern $REQUEST_LOG. Exiting."
  exit 1
else
  echo "Request log files found: $(ls $REQUEST_LOG)"
fi

# Loki URL and Headers
LOKI_URL="http://aeae2830b4456423599b02891a824617-efa7884bdea4bbc1.elb.eu-west-1.amazonaws.com/loki/api/v1/push"
LOKI_HEADER="X-Scope-OrgID: D4F80F363D152557B506E690D734091A"

# Generate blacklist regex dynamically
generate_blacklist_regex() {
  local file=$1
  if [[ -f "$file" ]]; then
    tr '\n' '|' < "$file" | sed 's/|$//'
  else
    echo ".*"
  fi
}

# Blacklist Patterns
DOMAIN_BLACKLIST_REGEX=$(generate_blacklist_regex "$DOMAIN_BLACKLIST")
MARKETPLACEID_BLACKLIST_REGEX=$(generate_blacklist_regex "$MARKETPLACEID_BLACKLIST")

# Generate Promtail Configuration
cat <<EOF > $OUTPUT_CONFIG
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: ${LOKI_URL}
    headers:
      ${LOKI_HEADER}
    backoff_config:
      min_period: 500ms      # Minimum backoff on retry
      max_period: 30s        # Maximum backoff on retry
    timeout: 10s             # Timeout for each push request

limits_config:
  max_streams: 5000           # Prevent stream starvation
  max_line_size: 2MB          # Allow large log lines

scrape_configs:

  # Access Logs
  - job_name: access-logs-${SERVER_NAME}
    static_configs:
      - targets: ['localhost']
        labels:
          job: access-logs-${SERVER_NAME}
          global_log_type: access-logs
          host: ${SERVER_NAME}
          filename: ${ACCESS_LOG}
          __path__: ${ACCESS_LOG}
    pipeline_stages:
      - regex:
          expression: '^(?P<client_ip>\S+) \S+ (?P<domain>\S+) .*'
      - drop:
          expression: "${DOMAIN_BLACKLIST_REGEX}"  # Drop blacklisted domains dynamically

  # Debug Logs
  - job_name: debug-logs-${SERVER_NAME}
    static_configs:
      - targets: ['localhost']
        labels:
          job: debug-logs-${SERVER_NAME}
          global_log_type: debug-logs
          host: ${SERVER_NAME}
          filename: ${DEBUG_LOG}
          __path__: ${DEBUG_LOG}
    pipeline_stages:
      - regex:
          expression: '^\[(?P<timestamp>[^\]]+)\] (?P<loglevel>\S+) \[(?P<requestid>\S+)\] (?P<marketplaceid>\S+): .*'
      - drop:
          expression: "${MARKETPLACEID_BLACKLIST_REGEX}"  # Drop blacklisted marketplace IDs dynamically
      - output:
          source: message

  # Request Logs
  - job_name: request-logs-${SERVER_NAME}
    static_configs:
      - targets: ['localhost']
        labels:
          job: request-logs-${SERVER_NAME}
          global_log_type: request-logs
          host: ${SERVER_NAME}
          filename: ${REQUEST_LOG}
          __path__: ${REQUEST_LOG}
    pipeline_stages:
      - regex:
          expression: '^\[(?P<timestamp>[^\]]+)\] (?P<loglevel>\S+) \[(?P<requestid>\S+)\] (?P<marketplaceid>\S+): .*'
      - drop:
          expression: "${MARKETPLACEID_BLACKLIST_REGEX}"  # Drop blacklisted marketplace IDs dynamically
      - output:
          source: message

EOF

echo "Promtail configuration generated successfully at ${OUTPUT_CONFIG}"

