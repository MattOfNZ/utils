# Utils

General utilities

This repository contains a collection of utility scripts and tools for various platforms and services.

## Available Tools

### AWS Utilities

#### ECS/Fargate Management Utilities
- **ecs-exec.sh**: Container Shell Access - A terminal UI for quickly attaching to containers on ECS
- **ecs-logs.sh**: Log Viewer - View and filter CloudWatch logs for ECS tasks
- **ecs-restart.sh**: Task Restart Utility - Restart ECS tasks and services
- **ecs-deploy.sh**: Deployment Utility - Force new deployments of ECS services and update service configurations
- **ecs-status.py**: Status Information Tool - View detailed status information for ECS resources

#### Elastic Beanstalk Utilities
- **get-env-vars.sh**: Script to retrieve environment variables from Elastic Beanstalk environments

#### S3 Utilities
- **presign-upload-url.py**: Generate pre-signed URLs for S3 uploads

#### Parameter Store Utilities
- **compare-keys.sh**: Compare parameters between two Parameter Store prefixes with detailed analysis and sync script generation
- **parameters-to-json.sh**: Retrieve AWS Parameter Store parameters as JSON with optional decryption

### Database Utilities

#### PostgreSQL Utilities
- **index_sizes.sql**: Query to check the size of indexes in a PostgreSQL database
- **quick_schema_review.sql**: SQL script for a quick review of a PostgreSQL database schema
- **quick_schema_review_markdown.sql**: Generate markdown documentation for PostgreSQL database schema
- **quick_select_insert_update.sql**: Generate SELECT, INSERT, and UPDATE SQL statements for tables
- **tables_sizes.sql**: Query to check the sizes of tables in a PostgreSQL database

#### SQL Server Utilities
- **running_agent_jobs.sql**: Query to check currently running SQL Server Agent jobs

### Windows Utilities

#### Analysis Tools
- **get-bsod-in-last-48hrs.ps1**: PowerShell script to check for blue screen of death events in the last 48 hours
- **get-recent-windows-updates.ps1**: PowerShell script to list recently installed Windows updates

## Installation

Clone the repository to get access to all utilities:

```bash
git clone https://github.com/MattOfNZ/utils.git
cd utils
```

Individual scripts can be run directly from their respective directories. Refer to each tool's documentation or run with `--help` for usage instructions.