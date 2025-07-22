#!/bin/bash

# Contabo Storage VPS Setup - Dual Archive Nodes
# Run this on VPS 1 and VPS 2

set -e

echo "=== Contabo Storage VPS Subtensor Setup ==="
echo "Deploying 2 archive nodes with no rate limits..."

# Get public IP
VPS_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip)
echo "VPS IP: $VPS_IP"

# Update system
echo "Updating system packages..."
apt-get update && apt-get upgrade -y
apt-get install -y docker.io docker-compose htop iotop ncdu curl wget jq

# Enable Docker
systemctl enable docker
systemctl start docker

# Add current user to docker group if not root
if [ "$EUID" -ne 0 ]; then
    usermod -aG docker $USER
fi

# Create directory structure
echo "Creating storage directories..."
mkdir -p /home/subtensor/{node1,node2}/{data,logs}
chmod -R 755 /home/subtensor

# Create Docker Compose configuration
echo "Creating Docker Compose configuration..."
cat > /root/docker-compose.yml << 'EOF'
version: '3.8'

services:
  subtensor-1:
    image: opentensor/subtensor:latest
    container_name: archive-node-1
    hostname: archive-node-1
    restart: unless-stopped
    command: >
      --base-path=/data
      --chain=finney
      --pruning=archive
      --state-pruning=archive
      --rpc-external
      --rpc-cors=all
      --rpc-methods=safe
      --rpc-max-connections=10000
      --rpc-rate-limit=0
      --rpc-rate-limit-whitelisted-ips=0.0.0.0/0
      --ws-external
      --ws-max-connections=10000
      --in-peers=500
      --out-peers=500
      --db-cache=8192
      --state-cache-size=2147483648
      --max-runtime-instances=8
      --sync=warp
      --port=30333
      --rpc-port=9933
      --ws-port=9944
      --prometheus-external
      --prometheus-port=9615
    volumes:
      - /home/subtensor/node1/data:/data
      - /home/subtensor/node1/logs:/var/log/subtensor
    ports:
      - "9933:9933"
      - "9944:9944"
      - "30333:30333"
      - "9615:9615"
    deploy:
      resources:
        limits:
          cpus: '7'
          memory: 24G
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9933/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  subtensor-2:
    image: opentensor/subtensor:latest
    container_name: archive-node-2
    hostname: archive-node-2
    restart: unless-stopped
    command: >
      --base-path=/data
      --chain=finney
      --pruning=archive
      --state-pruning=archive
      --rpc-external
      --rpc-cors=all
      --rpc-methods=safe
      --rpc-max-connections=10000
      --rpc-rate-limit=0
      --rpc-rate-limit-whitelisted-ips=0.0.0.0/0
      --ws-external
      --ws-max-connections=10000
      --in-peers=500
      --out-peers=500
      --db-cache=8192
      --state-cache-size=2147483648
      --max-runtime-instances=8
      --sync=warp
      --port=30334
      --rpc-port=9934
      --ws-port=9945
      --prometheus-external
      --prometheus-port=9616
    volumes:
      - /home/subtensor/node2/data:/data
      - /home/subtensor/node2/logs:/var/log/subtensor
    ports:
      - "9934:9934"
      - "9945:9945"
      - "30334:30334"
      - "9616:9616"
    deploy:
      resources:
        limits:
          cpus: '7'
          memory: 24G
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9934/health"]
      interval: 30s
      timeout: 10s
      retries: 3

networks:
  default:
    driver: bridge

EOF

# Create systemd service for auto-start
echo "Creating systemd service..."
cat > /etc/systemd/system/subtensor-compose.service << 'EOF'
[Unit]
Description=Subtensor Archive Nodes
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/root
ExecStart=/usr/bin/docker-compose up -d
ExecStop=/usr/bin/docker-compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

# Enable the service
systemctl daemon-reload
systemctl enable subtensor-compose

# Pull images first to avoid timeout
echo "Pulling Docker images..."
docker pull opentensor/subtensor:latest

# Start the services
echo "Starting Subtensor archive nodes..."
cd /root
docker-compose up -d

# Wait for containers to start
echo "Waiting for containers to initialize..."
sleep 15

# Show status
echo ""
echo "=== Deployment Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== Node Information ==="
echo "VPS IP: $VPS_IP"
echo "Node 1 RPC: http://$VPS_IP:9933"
echo "Node 2 RPC: http://$VPS_IP:9934"
echo "Node 1 WebSocket: ws://$VPS_IP:9944"
echo "Node 2 WebSocket: ws://$VPS_IP:9945"
echo "Node 1 Prometheus: http://$VPS_IP:9615"
echo "Node 2 Prometheus: http://$VPS_IP:9616"

echo ""
echo "=== Useful Commands ==="
echo "Check node 1 logs: docker logs -f archive-node-1"
echo "Check node 2 logs: docker logs -f archive-node-2"
echo "Check system health: curl -X POST -H 'Content-Type: application/json' -d '{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"system_health\"}' http://$VPS_IP:9933"
echo "Check sync status: curl -X POST -H 'Content-Type: application/json' -d '{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"system_syncState\"}' http://$VPS_IP:9933"
echo "Restart services: systemctl restart subtensor-compose"

echo ""
echo "=== Initial Sync Info ==="
echo "Archive nodes will take 24-48 hours to fully synchronize."
echo "Monitor sync progress with the commands above."
echo "Setup complete!"