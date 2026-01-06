# DevEnv - Kubernetes Development Environment

A comprehensive automation toolkit for setting up and managing a local Kubernetes development environment using microk8s, with integrated support for Kafka, MongoDB, and Kong API Gateway.

## Overview

DevEnv automates the complete lifecycle of a Kubernetes development environment, from initial installation through daily operations. It handles the complexity of configuring networking, storage, load balancing, and deploying common infrastructure services.

## Features

- **One-command setup** - Complete Kubernetes environment in minutes
- **Integrated services** - Kafka (Strimzi), MongoDB (Percona), Kong API Gateway
- **LoadBalancer support** - MetalLB for external service access
- **Advanced networking** - Kube-OVN for production-like network features
- **Dashboard access** - Kubernetes Dashboard with TLS via Kong ingress
- **Idempotent operations** - Safe to run multiple times
- **Graceful lifecycle management** - Clean start, stop, and remove operations

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         DevEnv Environment                          │
├─────────────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐              │
│  │    Kafka     │  │   MongoDB    │  │     Kong     │              │
│  │  (Strimzi)   │  │  (Percona)   │  │ API Gateway  │              │
│  │  3 brokers   │  │  3 replicas  │  │   DB-less    │              │
│  └──────────────┘  └──────────────┘  └──────────────┘              │
├─────────────────────────────────────────────────────────────────────┤
│                      microk8s Kubernetes 1.33                       │
│  ┌────────┐ ┌─────────┐ ┌─────────┐ ┌──────────┐ ┌──────────────┐  │
│  │ CoreDNS│ │Dashboard│ │ MetalLB │ │ Registry │ │Metrics Server│  │
│  └────────┘ └─────────┘ └─────────┘ └──────────┘ └──────────────┘  │
│  ┌──────────────────┐  ┌───────────────────────────────────────┐   │
│  │    Kube-OVN      │  │        Hostpath Storage               │   │
│  │ (CNI + Network)  │  │     (PersistentVolumes)               │   │
│  └──────────────────┘  └───────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Ubuntu/Debian-based Linux (tested on Fedora/Nobara as well)
- sudo/root access
- snapd installed
- TLS certificates (see [Certificates Setup](#certificates-setup))

### Certificates Setup

Before running DevEnv, you must create the `certificates/` directory and populate it with your TLS certificates. These are used for the Kubernetes Dashboard ingress.

```bash
mkdir -p certificates/
```

**Required files** (naming convention: `<domain>-domain.crt` and `<domain>-domain.key`):

```
certificates/
├── <your-domain>-domain.crt    # TLS certificate
└── <your-domain>-domain.key    # Private key
```

**Example** for domain `devenv.dev`:

```
certificates/
├── devenv.dev-domain.crt
└── devenv.dev-domain.key
```

The domain name must match the `DASHBOARD_CERTIFICATE` environment variable (default: `devenv.dev`).

**Generating self-signed certificates** (for development):

```bash
# Generate self-signed certificate for devenv.dev
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout certificates/devenv.dev-domain.key \
  -out certificates/devenv.dev-domain.crt \
  -subj "/CN=*.devenv.dev" \
  -addext "subjectAltName=DNS:*.devenv.dev,DNS:devenv.dev"
```

**Using Let's Encrypt or other CA certificates**:

Simply copy your certificate and key files with the correct naming convention:

```bash
cp /path/to/fullchain.pem certificates/yourdomain.com-domain.crt
cp /path/to/privkey.pem certificates/yourdomain.com-domain.key
```

### Installation

```bash
# Clone the repository
git clone <repository-url> devenv
cd devenv

# Set up certificates (see above)
mkdir -p certificates/
# ... add your certificates ...

# Install everything (microk8s + plugins + Kong)
sudo ./devenv.sh microk8s refresh

# Install Kafka
sudo ./devenv.sh kafka refresh

# Install MongoDB
sudo ./devenv.sh mongodb refresh
```

### Verify Installation

```bash
# Check microk8s status
microk8s status

# Check all pods
microk8s kubectl get pods -A

# Run E2E tests
./tests/run_tests.sh
```

## Usage

### Command Syntax

```bash
./devenv.sh <flow> <action>
```

### Flows

| Flow | Description |
|------|-------------|
| `microk8s` | Kubernetes cluster and plugins |
| `kafka` | Kafka cluster (Strimzi operator) |
| `mongodb` | MongoDB cluster (Percona operator) |

### Actions

| Action | Description |
|--------|-------------|
| `refresh` | Install or update (idempotent) |
| `start` | Start stopped services |
| `stop` | Stop services (preserves data) |
| `restart` | Stop then start |
| `remove` | Completely remove |

### Examples

```bash
# Fresh install of everything
sudo ./devenv.sh microk8s refresh
sudo ./devenv.sh kafka refresh
sudo ./devenv.sh mongodb refresh

# Stop MongoDB (preserves PVCs)
sudo ./devenv.sh mongodb stop

# Start MongoDB
sudo ./devenv.sh mongodb start

# Remove Kafka completely
sudo ./devenv.sh kafka remove

# Remove everything including microk8s
sudo ./devenv.sh mongodb remove
sudo ./devenv.sh kafka remove
sudo ./devenv.sh microk8s remove
```

## Configuration

Configuration is done via environment variables. Set them before running `devenv.sh`:

### Version Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `MICROK8S_VERSION` | `1.33` | Kubernetes version |
| `KONG_VERSION` | `3.0.1` | Kong API Gateway version |
| `STRIMZI_VERSION` | `0.49.1` | Strimzi Kafka operator version |
| `KAFKA_VERSION` | `4.0.0` | Apache Kafka version |
| `PERCONA_OPERATOR_VERSION` | `1.21.2` | Percona operator version |
| `PERCONA_DB_VERSION` | `1.21.1` | Percona DB chart version |
| `PERCONA_MONGODB_VERSION` | `8.0.12-4` | MongoDB version |

### Feature Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `KONG_ENABLED` | `true` | Enable Kong API Gateway |
| `LOADBALANCER_NUM_OF_IP_ADDRESSES` | `16` | MetalLB IP pool size |
| `DASHBOARD_DOMAIN` | `k8s.devenv.dev` | Dashboard hostname |
| `DASHBOARD_CERTIFICATE` | `devenv.dev` | TLS certificate domain (must match files in `certificates/`) |
| `SLOW_MOTION_TEXT` | `true` | Animated text output |

### Example: Custom Configuration

```bash
export MICROK8S_VERSION=1.32
export KONG_ENABLED=false
export LOADBALANCER_NUM_OF_IP_ADDRESSES=32
export DASHBOARD_CERTIFICATE=mycompany.com
sudo -E ./devenv.sh microk8s refresh
```

## Components

### microk8s Plugins

| Plugin | Purpose |
|--------|---------|
| `kube-ovn` | Advanced CNI with network policies |
| `dns` | CoreDNS for service discovery |
| `dashboard` | Kubernetes Dashboard UI |
| `storage` | Hostpath storage provisioner |
| `registry` | Local container registry (localhost:32000) |
| `metrics-server` | Resource metrics API |
| `metallb` | LoadBalancer implementation |
| `helm3` | Helm package manager |

### Kafka (Strimzi)

- **Version**: Kafka 4.0.0 with KRaft (no ZooKeeper)
- **Topology**: 3 combined controller+broker nodes
- **Access**: LoadBalancer services for external access
- **Management**: Entity operator for topics and users

### MongoDB (Percona)

- **Version**: Percona Server for MongoDB 8.0
- **Topology**: 3-node replica set (no sharding)
- **Access**: LoadBalancer per replica
- **Storage**: Persistent volumes via hostpath

### Kong API Gateway

- **Mode**: DB-less (declarative configuration)
- **Features**: Ingress controller for Kubernetes
- **Dashboard**: Routes to Kubernetes Dashboard with TLS

## Network Architecture

MetalLB assigns LoadBalancer IPs from your local network:

```
Base IP (your machine):     192.168.178.20
Kong API Gateway:           192.168.178.21
Kafka Bootstrap:            192.168.178.22
Kafka Broker 0:             192.168.178.23
Kafka Broker 1:             192.168.178.24
Kafka Broker 2:             192.168.178.25
MongoDB Replica 0:          192.168.178.26
MongoDB Replica 1:          192.168.178.27
MongoDB Replica 2:          192.168.178.28
... (up to +16 addresses)
```

## Project Structure

```
devenv/
├── devenv.sh              # Main entry point
├── README.md              # This file
├── LICENSE                # MIT License
├── certificates/          # TLS certificates (manually created)
│   ├── <domain>-domain.crt
│   └── <domain>-domain.key
├── devenv/                # Library modules
│   ├── libmicrok8s.sh     # microk8s management
│   ├── libkafka.sh        # Kafka (Strimzi) management
│   ├── libmongodb.sh      # MongoDB (Percona) management
│   ├── libkong.sh         # Kong API Gateway
│   ├── libk8s.sh          # Kubernetes utilities
│   ├── libhelm.sh         # Helm utilities
│   ├── libnetwork.sh      # Network utilities
│   ├── libflows.sh        # Flow orchestration
│   ├── liblog.sh          # Logging utilities
│   ├── libversion.sh      # Version information
│   ├── libwelcome.sh      # Welcome banner
│   ├── libuser.sh         # User detection
│   ├── libos.sh           # OS utilities
│   ├── libcurl.sh         # HTTP utilities
│   ├── libgit.sh          # Git utilities
│   └── libdevenv.sh       # DevEnv utilities
└── tests/                 # E2E test suite
    ├── README.md          # Test documentation
    ├── run_tests.sh       # Test runner
    ├── lib/testlib.sh     # Test utilities
    └── e2e/               # Test suites
        ├── test_microk8s.sh
        ├── test_kafka.sh
        └── test_mongodb.sh
```

## Testing

The project includes a comprehensive E2E test suite with 37 tests:

```bash
# Run all non-destructive tests
./tests/run_tests.sh

# Run specific suite
./tests/run_tests.sh mongodb

# Run including destructive tests (remove/refresh)
./tests/run_tests.sh --destructive

# List available suites
./tests/run_tests.sh --list
```

### Test Coverage

| Suite | Tests | Coverage |
|-------|-------|----------|
| microk8s | 13 | Plugins, pods, services, Kong, refresh |
| kafka | 11 | CRDs, operator, cluster, LoadBalancers, refresh, remove |
| mongodb | 13 | CRDs, operator, replicas, secrets, PVCs, stop, start, refresh, remove |

See [tests/README.md](tests/README.md) for detailed testing documentation.

## Troubleshooting

### microk8s won't start

```bash
# Check snap status
snap list microk8s

# Check microk8s logs
sudo journalctl -u snap.microk8s.daemon-kubelite
```

### Pods stuck in Pending

```bash
# Check node resources
microk8s kubectl describe nodes

# Check PVC status (for stateful services)
microk8s kubectl get pvc -A
```

### LoadBalancer stuck in Pending

```bash
# Verify MetalLB is running
microk8s kubectl get pods -n metallb-system

# Check MetalLB configuration
microk8s kubectl get ipaddresspool -n metallb-system
```

### Cannot connect to services

```bash
# Check service external IPs
microk8s kubectl get svc -A | grep LoadBalancer

# Verify network connectivity
ping <LoadBalancer-IP>
```

### Certificate errors on Dashboard

```bash
# Verify certificates exist
ls -la certificates/

# Check certificate names match DASHBOARD_CERTIFICATE
echo $DASHBOARD_CERTIFICATE

# Verify secret was created
microk8s kubectl get secret ingress-tls-secrets -n kubernetes-dashboard
```

### Clean restart

```bash
# Remove everything and start fresh
sudo ./devenv.sh mongodb remove
sudo ./devenv.sh kafka remove
sudo ./devenv.sh microk8s remove

# Reinstall
sudo ./devenv.sh microk8s refresh
```

## Service Access

### Kubernetes Dashboard

```
URL: https://k8s.devenv.dev (or your DASHBOARD_DOMAIN)
Token: microk8s kubectl describe secret -n kube-system microk8s-dashboard-token
```

Add the dashboard domain to `/etc/hosts` pointing to Kong's LoadBalancer IP:

```
192.168.178.21  k8s.devenv.dev
```

### MongoDB

```bash
# Connection string (from any replica)
mongodb://userAdmin:<password>@192.168.178.26:27017

# Get credentials
microk8s kubectl get secret mongodb-psmdb-db-secrets -n mongodb \
  -o jsonpath='{.data.MONGODB_USER_ADMIN_PASSWORD}' | base64 -d
```

### Kafka

```bash
# Bootstrap server
192.168.178.22:9094

# Individual brokers
192.168.178.23:9094
192.168.178.24:9094
192.168.178.25:9094
```

### Container Registry

```bash
# Push images to local registry
docker tag myimage localhost:32000/myimage
docker push localhost:32000/myimage
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run the test suite: `./tests/run_tests.sh --destructive`
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.

Copyright (c) 2022-2025 Felix Jacobsen
