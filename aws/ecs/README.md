# AWS ECS/Fargate Management Utilities

This directory contains a collection of utility scripts for managing ECS/Fargate deployments. These scripts are designed to be run from AWS CloudShell or any environment with the AWS CLI installed.

## Prerequisites

- AWS CLI configured with appropriate permissions
- `jq` installed (for JSON parsing in bash scripts)
- Python 3.6+ (for Python scripts only)
- boto3 (for Python scripts only, pre-installed in AWS CloudShell)

## Available Utilities

### 1. `ecs-exec.sh` - Container Shell Access

A terminal UI for quickly attaching to containers on ECS which have "ECS Exec" enabled.

**Usage:**
```bash
./ecs-exec.sh
```

**Features:**
- List available ECS clusters
- List tasks within a selected cluster
- List containers within a selected task
- Connect to a container using ECS Exec

### 2. `ecs-logs.sh` - Log Viewer

View and filter CloudWatch logs for ECS tasks.

**Usage:**
```bash
./ecs-logs.sh
```

**Features:**
- View recent logs from ECS task containers
- Tail logs in real-time (follow mode)
- Search logs for specific patterns (grep functionality)
- Navigate through clusters, tasks, and containers

### 3. `ecs-restart.sh` - Task Restart Utility

Restart ECS tasks and services.

**Usage:**
```bash
./ecs-restart.sh
```

**Features:**
- Restart individual tasks
- Restart all tasks in a service
- Choose between restarting methods:
  - Force new deployment (zero downtime)
  - Stop all tasks (service scheduler will start replacements)
- Monitor deployment progress

### 4. `ecs-deploy.sh` - Deployment Utility

Force new deployments of ECS services and update service configurations.

**Usage:**
```bash
./ecs-deploy.sh
```

**Features:**
- Force new deployment (no changes)
- Deploy with a different task definition
- Update task count
- View service details
- Monitor deployment progress

### 5. `ecs-status.py` - Status Information Tool

Python script for retrieving detailed status information about ECS clusters, services, and tasks.

**Usage:**
```bash
./ecs-status.py [--profile PROFILE] [--region REGION]
```

**Features:**
- View cluster summaries
- View detailed service information
- View task details
- View all resources (cluster → services → tasks)
- Color-coded status indicators

## Example Usage Scenarios

### Scenario 1: Troubleshooting a Service

1. Use `ecs-status.py` to view the service status and recent events
2. Use `ecs-logs.sh` to check logs for errors
3. If needed, use `ecs-restart.sh` to restart problematic tasks
4. Use `ecs-exec.sh` to get a shell into a container for deeper inspection

### Scenario 2: Deploying a New Version

1. Use `ecs-deploy.sh` to force a new deployment or update task definition
2. Monitor the deployment progress
3. Use `ecs-logs.sh` to verify the new deployment is working correctly

### Scenario 3: Scaling a Service

1. Use `ecs-status.py` to check current service configuration
2. Use `ecs-deploy.sh` to update the desired task count
3. Monitor the scaling operation

## License

This project is licensed under the MIT License.