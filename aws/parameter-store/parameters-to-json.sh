#!/bin/bash

# AWS Parameter Store retrieval script
# Usage: ./parameters-to-json.sh <prefix> [--decrypt|-d]
# Example: ./parameters-to-json.sh /myapp-prod/config --decrypt

# Default values
PREFIX=""
DECRYPT=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--decrypt)
            DECRYPT=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 <prefix> [--decrypt|-d]"
            echo ""
            echo "Arguments:"
            echo "  <prefix>      AWS Parameter Store path prefix (e.g., /myapp-prod/config)"
            echo "  --decrypt, -d Optional flag to decrypt SecureString parameters"
            echo ""
            echo "Examples:"
            echo "  $0 /myapp-prod/config"
            echo "  $0 /myapp-prod/config --decrypt"
            exit 0
            ;;
        *)
            if [[ -z "$PREFIX" ]]; then
                PREFIX="$1"
            else
                echo "Error: Unknown argument '$1'"
                echo "Usage: $0 <prefix> [--decrypt|-d]"
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if prefix is provided
if [[ -z "$PREFIX" ]]; then
    echo "Error: Prefix is required"
    echo "Usage: $0 <prefix> [--decrypt|-d]"
    echo "Example: $0 /myapp-prod/config --decrypt"
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI is not installed or not in PATH"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed or not in PATH"
    echo "Please install jq to parse JSON output"
    exit 1
fi

# Build and execute AWS CLI command
echo "Retrieving parameters with prefix: $PREFIX" >&2
if [[ "$DECRYPT" == true ]]; then
    echo "Decryption: enabled" >&2
    PARAMS=$(aws ssm get-parameters-by-path --path "$PREFIX" --with-decryption --recursive --output json 2>/dev/null)
else
    echo "Decryption: disabled (values will be masked for SecureString parameters)" >&2
    PARAMS=$(aws ssm get-parameters-by-path --path "$PREFIX" --recursive --output json 2>/dev/null)
fi

# Check if AWS CLI command was successful
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to retrieve parameters from AWS Parameter Store" >&2
    echo "Please check:" >&2
    echo "  - AWS credentials are configured" >&2
    echo "  - You have ssm:GetParametersByPath permission" >&2
    echo "  - The prefix path exists" >&2
    exit 1
fi

# Check if any parameters were found
PARAM_COUNT=$(echo "$PARAMS" | jq '.Parameters | length')
if [[ "$PARAM_COUNT" -eq 0 ]]; then
    echo "No parameters found with prefix: $PREFIX" >&2
    echo "{}"
    exit 0
fi

echo "Found $PARAM_COUNT parameter(s)" >&2

# Parse and format the output
# Extract suffix by removing the prefix and any leading slash
echo "$PARAMS" | jq -r --arg prefix "$PREFIX" '
    .Parameters[] | 
    {
        ((.Name | sub("^" + $prefix + "/?"; ""))): .Value
    }
' | jq -s 'add // {} | to_entries | sort_by(.key) | from_entries'