# Utils Repository Copilot Instructions

**ALWAYS follow these instructions first. Only fallback to additional search and context gathering if the information here is incomplete or found to be in error.**

## Repository Overview
This is a collection of standalone utility scripts organized by platform and service. Scripts do not require compilation or building - they are executable as-is. The repository contains AWS utilities, database utilities, and Windows analysis tools.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the information here.

## Working Effectively

### Prerequisites and Dependencies
Install and configure dependencies in this order:

1. **AWS CLI (for AWS utilities)**:
   ```bash
   # AWS CLI is typically pre-installed in most environments
   # Verify installation:
   which aws
   aws --version
   
   # Configure credentials (required for AWS utilities):
   aws configure
   # Or set environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION
   ```

2. **jq (for shell scripts that parse JSON)**:
   ```bash
   # Verify installation:
   which jq
   jq --version
   
   # Install if needed (Ubuntu/Debian):
   apt-get update && apt-get install -y jq
   ```

3. **Python 3 with boto3 (for Python scripts)**:
   ```bash
   # Verify installation:
   python3 --version  # Should be 3.6+
   python3 -c "import boto3; print('boto3 version:', boto3.__version__)"
   
   # Install boto3 if needed:
   pip3 install boto3
   ```

4. **PostgreSQL client (for database scripts)**:
   ```bash
   # Verify installation:
   which psql
   psql --version
   
   # Install if needed (Ubuntu/Debian):
   apt-get update && apt-get install -y postgresql-client
   ```

5. **PowerShell (for Windows utilities - Linux/Mac only)**:
   ```bash
   # PowerShell utilities are designed for Windows environments
   # On Linux/Mac, install PowerShell Core if needed:
   # https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell
   ```

### Repository Structure Navigation
```bash
# Repository root structure:
/home/runner/work/utils/utils/
├── README.md                    # Overview and usage
├── LICENSE                      # MIT License
├── aws/                         # AWS utility scripts
│   ├── ecs/                     # ECS/Fargate management tools
│   ├── elastic-beanstalk/       # Elastic Beanstalk utilities
│   ├── parameter-store/         # Parameter Store utilities
│   └── s3/                      # S3 utilities
├── postgres/                    # PostgreSQL utility scripts
├── sql-server/                  # SQL Server utility scripts
└── windows/                     # Windows analysis tools
    └── analysis/                # System analysis PowerShell scripts
```

### Running Utilities

#### AWS Utilities (Execution time: < 5 seconds each)
**NEVER CANCEL: All AWS utilities complete within 5 seconds unless network issues occur.**

```bash
# Ensure executable permissions:
chmod +x aws/ecs/*.sh aws/parameter-store/*.sh aws/elastic-beanstalk/*.sh

# ECS utilities (require AWS CLI configured with ECS permissions):
./aws/ecs/ecs-exec.sh           # Interactive shell access to ECS containers
./aws/ecs/ecs-logs.sh           # View CloudWatch logs for ECS tasks
./aws/ecs/ecs-restart.sh        # Restart ECS tasks and services
./aws/ecs/ecs-deploy.sh         # Deploy ECS services
python3 aws/ecs/ecs-status.py   # View detailed ECS status information

# Parameter Store utilities:
./aws/parameter-store/parameters-to-json.sh /prefix/path        # Get parameters as JSON
./aws/parameter-store/parameters-to-json.sh /prefix/path -d     # Get with decryption
./aws/parameter-store/compare-keys.sh                           # Compare parameter keys

# S3 utilities:
python3 aws/s3/presign-upload-url.py                           # Generate presigned upload URLs

# Elastic Beanstalk utilities:
./aws/elastic-beanstalk/get-env-vars.sh                        # Get environment variables
```

#### Database Utilities (Execution time: varies by database size)
**NEVER CANCEL: SQL queries may take 1-30 minutes depending on database size. Set timeout to 45+ minutes.**

```bash
# PostgreSQL utilities (require psql and database connection):
psql -h hostname -U username -d database -f postgres/tables_sizes.sql
psql -h hostname -U username -d database -f postgres/index_sizes.sql
psql -h hostname -U username -d database -f postgres/quick_schema_review.sql
psql -h hostname -U username -d database -f postgres/quick_schema_review_markdown.sql
psql -h hostname -U username -d database -f postgres/quick_select_insert_update.sql

# SQL Server utilities (require sqlcmd):
sqlcmd -S server -d database -i sql-server/running_agent_jobs.sql
```

#### Windows Utilities (Execution time: < 30 seconds each)
```powershell
# Windows analysis tools (require PowerShell on Windows):
powershell -ExecutionPolicy Bypass -File windows/analysis/get-recent-windows-updates.ps1
powershell -ExecutionPolicy Bypass -File windows/analysis/get-bsod-in-last-48hrs.ps1
```

### Validation and Testing

#### Always validate functionality using these steps:

1. **AWS Utilities Validation**:
   ```bash
   # Verify AWS credentials are configured:
   aws sts get-caller-identity
   
   # Test help functionality (should complete in < 2 seconds):
   ./aws/ecs/ecs-exec.sh --help
   python3 aws/ecs/ecs-status.py --help
   ./aws/parameter-store/parameters-to-json.sh
   ```

2. **Database Utilities Validation**:
   ```bash
   # Test SQL script syntax (should complete in < 1 second):
   head -20 postgres/tables_sizes.sql
   head -20 postgres/quick_schema_review.sql
   
   # Verify PostgreSQL client:
   psql --version
   ```

3. **Python Scripts Validation**:
   ```bash
   # Test Python environment (should complete in < 1 second):
   python3 -c "import boto3; print('Environment ready')"
   
   # Test script loading (should complete in < 2 seconds):
   python3 -c "exec(open('aws/ecs/ecs-status.py').read().split('if __name__')[0])"
   ```

#### Validation Scenarios
ALWAYS run through these scenarios after making changes:

1. **AWS Script Modification Validation**:
   - Run the modified script with `--help` flag
   - Verify script starts without syntax errors
   - Test with invalid AWS credentials to ensure proper error handling

2. **Database Script Validation**:
   - Check SQL syntax by loading the script content
   - Verify file permissions allow reading

3. **Overall Repository Integrity**:
   - Ensure all shell scripts maintain executable permissions
   - Verify no scripts were accidentally deleted

### Common Tasks and Expected Timing

#### File Operations (< 1 second each)
```bash
# View script help:
./aws/ecs/ecs-exec.sh --help                    # < 1 second
python3 aws/ecs/ecs-status.py --help           # < 1 second

# Check script permissions:
ls -la aws/ecs/*.sh                             # < 1 second
ls -la aws/parameter-store/*.sh                 # < 1 second
```

#### Environment Validation (< 5 seconds total)
```bash
# Verify all dependencies:
which aws && which jq && which python3 && which psql     # < 2 seconds
python3 -c "import boto3"                                 # < 1 second
aws --version                                             # < 2 seconds
```

#### Script Execution (varies)
- **AWS utilities**: < 5 seconds (unless AWS API is slow)
- **Database queries**: 1-30 minutes (depending on database size)
- **Windows utilities**: < 30 seconds

### Repository-Specific Guidelines

#### When Modifying AWS Utilities:
- Always test with `--help` flag first
- Ensure AWS CLI error handling is preserved
- Test with missing credentials to verify error messages
- Verify jq dependency usage remains functional

#### When Modifying Database Scripts:
- Test SQL syntax before committing
- Ensure compatibility with PostgreSQL/SQL Server versions
- Check for potential long-running queries and document timing

#### When Adding New Utilities:
- Follow existing directory structure (organize by platform/service)
- Add appropriate executable permissions for shell scripts
- Include help functionality (--help flag)
- Update README.md with new utility documentation

### Troubleshooting Common Issues

#### AWS Utilities Issues:
```bash
# Missing AWS credentials:
aws configure
# Or set: export AWS_ACCESS_KEY_ID=..., AWS_SECRET_ACCESS_KEY=..., AWS_DEFAULT_REGION=...

# Missing jq:
apt-get update && apt-get install -y jq

# Permission denied:
chmod +x aws/ecs/*.sh aws/parameter-store/*.sh
```

#### Database Utilities Issues:
```bash
# Missing PostgreSQL client:
apt-get update && apt-get install -y postgresql-client

# Connection issues:
psql -h hostname -U username -d database -c "SELECT 1;"
```

#### Python Script Issues:
```bash
# Missing boto3:
pip3 install boto3

# Python version too old:
python3 --version  # Should be 3.6+
```

### Testing and Quality Assurance

#### Before Committing Changes:
1. **Verify Dependencies**: Run environment validation commands above
2. **Test Help Functions**: Ensure `--help` flags work for modified scripts
3. **Check Permissions**: Verify executable permissions on shell scripts
4. **Syntax Validation**: Test script loading without execution

#### No Build or CI Process:
- This repository has no build process, CI pipelines, or automated testing
- Manual validation is the primary quality assurance method
- Scripts are designed to be self-contained and executable as-is

### Quick Reference Commands

```bash
# Repository overview:
ls -la                                          # < 1 second
find . -name "*.sh" | wc -l                    # Count shell scripts, < 1 second
find . -name "*.py" | wc -l                    # Count Python scripts, < 1 second
find . -name "*.sql" | wc -l                   # Count SQL scripts, < 1 second

# Dependency check:
which aws jq python3 psql                      # < 1 second

# AWS utilities listing:
ls -la aws/*/                                  # < 1 second

# Most frequently used commands:
./aws/ecs/ecs-exec.sh                         # Interactive ECS shell access
./aws/ecs/ecs-logs.sh                         # ECS log viewer
python3 aws/ecs/ecs-status.py                 # ECS status overview
```

### Environment-Specific Notes

- **AWS CloudShell**: All dependencies pre-installed, optimal environment
- **Linux/Ubuntu**: May need to install jq and PostgreSQL client
- **macOS**: May need to install dependencies via Homebrew
- **Windows**: PowerShell utilities work natively, other tools need WSL or manual installation
- **Containerized environments**: Ensure AWS credentials are properly mounted/configured

### CRITICAL REMINDERS

- **NEVER CANCEL** long-running database queries - they may take up to 30 minutes
- **ALWAYS** verify AWS credentials before running AWS utilities
- **ALWAYS** test `--help` functionality after modifying scripts
- **ALWAYS** maintain executable permissions on shell scripts
- Scripts are standalone - no compilation, building, or package management required
- Repository structure is service-oriented - navigate by platform/tool type