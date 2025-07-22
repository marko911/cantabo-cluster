# Contabo Storage VPS Subtensor Deployment

Deploy 5 Subtensor archive nodes across 3 Contabo Storage VPS instances with load balancing and no rate limits.

## Architecture

- **VPS 1**: 2 archive nodes (ports 9933-9934, 9944-9945)
- **VPS 2**: 2 archive nodes (ports 9933-9934, 9944-9945) 
- **VPS 3**: 1 archive node + HAProxy load balancer (port 9933, 9944, 80, 8080)

## Prerequisites

- 3x Contabo Storage VPS 50 instances
- Ubuntu 22.04/24.04 installed
- SSH access configured

## Deployment Steps

### 1. Deploy VPS 1 and VPS 2

```bash
# SSH into VPS 1
ssh root@VPS1_IP
curl -sSL https://raw.githubusercontent.com/your-repo/subtensor/main/deploy-dual-nodes.sh | bash

# SSH into VPS 2  
ssh root@VPS2_IP
curl -sSL https://raw.githubusercontent.com/your-repo/subtensor/main/deploy-dual-nodes.sh | bash
```

### 2. Deploy VPS 3 (with load balancer)

```bash
# SSH into VPS 3
ssh root@VPS3_IP

# Set the IPs of your other VPS instances
export VPS1_IP="YOUR_VPS1_IP"
export VPS2_IP="YOUR_VPS2_IP"

curl -sSL https://raw.githubusercontent.com/your-repo/subtensor/main/deploy-lb-node.sh | bash
```

### 3. Access Your Cluster

- **Load Balanced RPC**: `http://VPS3_IP/`
- **Load Balanced WebSocket**: `ws://VPS3_IP:8080/`
- **HAProxy Stats**: `http://VPS3_IP:8404/stats`
- **Individual nodes**: `http://VPS1_IP:9933`, `http://VPS1_IP:9934`, etc.

## Monitoring

```bash
# Check node status
curl -X POST -H "Content-Type: application/json" \
  -d '{"id":1,"jsonrpc":"2.0","method":"system_health"}' \
  http://VPS3_IP/

# Check sync progress
curl -X POST -H "Content-Type: application/json" \
  -d '{"id":1,"jsonrpc":"2.0","method":"system_syncState"}' \
  http://VPS3_IP/

# View logs
docker logs -f archive-node-1
```

## Costs

- 3x Storage VPS 50 (12-month): **€94.35/month**
- 42 vCPU, 150GB RAM, 4.2TB NVMe storage
- 96TB monthly traffic allowance