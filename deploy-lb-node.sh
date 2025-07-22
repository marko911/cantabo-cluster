#!/bin/bash

# Contabo Storage VPS Setup - Single Node + Load Balancer
# Run this on VPS 3

set -e

echo "=== Contabo Storage VPS 3 Setup ==="
echo "Deploying 1 archive node + HAProxy load balancer..."

# Check for required environment variables
if [ -z "$VPS1_IP" ] || [ -z "$VPS2_IP" ]; then
    echo "ERROR: Please set VPS1_IP and VPS2_IP environment variables"
    echo "Example: export VPS1_IP='1.2.3.4' && export VPS2_IP='5.6.7.8'"
    exit 1
fi

# Get public IP
VPS3_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipinfo.io/ip)
echo "VPS 3 IP: $VPS3_IP"
echo "VPS 1 IP: $VPS1_IP"  
echo "VPS 2 IP: $VPS2_IP"

# Update system
echo "Updating system packages..."
apt-get update && apt-get upgrade -y
apt-get install -y docker.io docker-compose htop iotop ncdu curl wget jq

# Enable Docker
systemctl enable docker
systemctl start docker

# Create directory structure
echo "Creating storage directories..."
mkdir -p /home/subtensor/node1/{data,logs}
mkdir -p /etc/haproxy
chmod -R 755 /home/subtensor

# Generate secure auth token
AUTH_TOKEN=$(openssl rand -hex 32)
echo "Generated auth token: $AUTH_TOKEN"
echo "IMPORTANT: Save this token - you'll need it for API requests!"
echo "$AUTH_TOKEN" > /home/subtensor/auth-token.txt
chmod 600 /home/subtensor/auth-token.txt

# Create HAProxy configuration
echo "Creating HAProxy configuration with auth..."
cat > /etc/haproxy/haproxy.cfg << EOF
global
    maxconn 10000
    log stdout local0
    daemon

defaults
    mode http
    timeout connect 5s
    timeout client 60s
    timeout server 60s
    option httplog
    option dontlognull
    retries 3

frontend subtensor_rpc_frontend
    bind *:80
    
    # Check for Authorization header with correct token
    http-request deny unless { req.hdr(Authorization) -m str "Bearer $AUTH_TOKEN" }
    
    default_backend rpc_nodes

backend rpc_nodes
    balance leastconn
    option httpchk GET /health
    http-check send meth GET uri /health
    
    server vps1-node1 $VPS1_IP:9933 check inter 10s fall 3 rise 2
    server vps1-node2 $VPS1_IP:9934 check inter 10s fall 3 rise 2
    server vps2-node1 $VPS2_IP:9933 check inter 10s fall 3 rise 2
    server vps2-node2 $VPS2_IP:9934 check inter 10s fall 3 rise 2
    server vps3-node1 127.0.0.1:9933 check inter 10s fall 3 rise 2

frontend subtensor_ws_frontend
    bind *:8080
    
    # WebSocket auth - check for token in Sec-WebSocket-Protocol header
    http-request deny unless { req.hdr(Sec-WebSocket-Protocol) -m str "$AUTH_TOKEN" }
    
    default_backend ws_nodes

backend ws_nodes
    balance leastconn
    
    server vps1-ws1 $VPS1_IP:9944 check
    server vps1-ws2 $VPS1_IP:9945 check
    server vps2-ws1 $VPS2_IP:9944 check
    server vps2-ws2 $VPS2_IP:9945 check
    server vps3-ws1 127.0.0.1:9944 check

frontend stats
    bind *:8404
    
    # Stats page auth
    http-request auth unless { http_auth(statsusers) }
    
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE

userlist statsusers
    user admin password $(openssl passwd -1 admin$AUTH_TOKEN)
EOF

# Create Docker Compose configuration
echo "Creating Docker Compose configuration..."
cat > /root/docker-compose.yml << 'EOF'
version: '3.8'

services:
  subtensor-1:
    image: ghcr.io/opentensor/subtensor:latest
    container_name: archive-node-1
    hostname: archive-node-1
    restart: unless-stopped
    entrypoint: ["node-subtensor"]
    command:
      - "--base-path=/data"
      - "--chain=./chainspecs/raw_spec_finney.json"
      - "--rpc-external"
      - "--rpc-cors=all"
      - "--no-mdns"
      - "--bootnodes=/dns/bootnode.finney.chain.opentensor.ai/tcp/30333/ws/p2p/12D3KooWRwbMb85RWnT8DSXSYMWQtuDwh4LJzndoRrTDotTR5gDC"
      - "--pruning=archive"
      - "--port=30333"
      - "--rpc-port=9933"
      - "--rpc-max-connections=10000"
      - "--rpc-rate-limit-whitelisted-ips=0.0.0.0/0"
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
          cpus: '10'
          memory: 40G
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
    networks:
      - subtensor-net

  haproxy:
    image: haproxy:2.8-alpine
    container_name: subtensor-loadbalancer
    restart: unless-stopped
    ports:
      - "80:80"      # RPC load balancer
      - "8080:8080"  # WebSocket load balancer  
      - "8404:8404"  # HAProxy stats page
    volumes:
      - /etc/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    depends_on:
      - subtensor-1
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 4G
    networks:
      - subtensor-net

networks:
  subtensor-net:
    driver: bridge

EOF

# Create systemd service
echo "Creating systemd service..."
cat > /etc/systemd/system/subtensor-compose.service << 'EOF'
[Unit]
Description=Subtensor Archive Node + Load Balancer
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

# Pull images
echo "Pulling Docker images..."
docker pull ghcr.io/opentensor/subtensor:latest
docker pull haproxy:2.8-alpine

# Start services
echo "Starting services..."
cd /root
docker-compose up -d

# Wait for services to start
echo "Waiting for services to initialize..."
sleep 20

# Show status
echo ""
echo "=== Deployment Status ==="
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

echo ""
echo "=== Load Balancer Endpoints ==="
echo "Primary RPC (Load Balanced): http://$VPS3_IP/"
echo "WebSocket (Load Balanced): ws://$VPS3_IP:8080/"
echo "HAProxy Stats: http://$VPS3_IP:8404/stats"
echo "Local Node RPC: http://$VPS3_IP:9933"
echo "Local Node WebSocket: ws://$VPS3_IP:9944"

echo ""
echo "=== Backend Nodes ==="
echo "VPS 1 Node 1: http://$VPS1_IP:9933"
echo "VPS 1 Node 2: http://$VPS1_IP:9934"
echo "VPS 2 Node 1: http://$VPS2_IP:9933"  
echo "VPS 2 Node 2: http://$VPS2_IP:9934"

echo ""
echo "=== Authentication Details ==="
echo "Auth token saved to: /home/subtensor/auth-token.txt"
echo "Current token: $(cat /home/subtensor/auth-token.txt)"

echo ""
echo "=== Test Commands ==="
echo "Test load balancer (with auth): curl -X POST -H 'Content-Type: application/json' -H 'Authorization: Bearer $(cat /home/subtensor/auth-token.txt)' -d '{\"id\":1,\"jsonrpc\":\"2.0\",\"method\":\"system_health\"}' http://$VPS3_IP/"
echo "Check HAProxy stats (will prompt for login - user: admin, pass: admin<token>):"
echo "  curl http://$VPS3_IP:8404/stats"
echo "View node logs: docker logs -f archive-node-1"
echo "View LB logs: docker logs -f subtensor-loadbalancer"

echo ""
echo "=== Security Notes ==="
echo "- RPC requires: Authorization: Bearer <token>"
echo "- WebSocket requires: Sec-WebSocket-Protocol: <token>"
echo "- Stats page requires: username 'admin', password 'admin<token>'"
echo "- Token is saved in /home/subtensor/auth-token.txt (readable only by root)"

echo ""
echo "Setup complete! Load balancer now has token authentication."