#!/bin/bash

# Script to snapshot environment variables from AWS Elastic Beanstalk

set -e  # Exit on any error

echo "=== AWS Elastic Beanstalk Environment Variables Snapshot ==="
echo

# Get application name
read -p "Enter your Elastic Beanstalk application name: " app_name

# Validate app name is not empty
if [ -z "$app_name" ]; then
    echo "Error: Application name cannot be empty"
    exit 1
fi

# Get environment name
read -p "Enter your Elastic Beanstalk environment name: " env_name

# Validate env name is not empty
if [ -z "$env_name" ]; then
    echo "Error: Environment name cannot be empty"
    exit 1
fi

# Generate default output filename
default_filename="${app_name}_${env_name}_env_vars.json"

# Allow user to edit the filename
echo
echo "Default output filename: $default_filename"
read -p "Press Enter to use default, or type a new filename: " custom_filename

# Use custom filename if provided, otherwise use default
if [ -n "$custom_filename" ]; then
    output_file="$custom_filename"
else
    output_file="$default_filename"
fi

# Add .json extension if not present
if [[ "$output_file" != *.json ]]; then
    output_file="${output_file}.json"
fi

echo
echo "Configuration:"
echo "  Application: $app_name"
echo "  Environment: $env_name"
echo "  Output file: $output_file"
echo

# Confirm before proceeding
read -p "Proceed with the snapshot? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 0
fi

echo
echo "Fetching environment variables..."

# Execute the AWS CLI command
aws elasticbeanstalk describe-configuration-settings \
    --application-name "$app_name" \
    --environment-name "$env_name" \
    --query "ConfigurationSettings[0].OptionSettings[?Namespace=='aws:elasticbeanstalk:application:environment'].{Key:OptionName,Value:Value}" \
    > "$output_file"

# Check if the command was successful
if [ $? -eq 0 ]; then
    echo "✓ Environment variables successfully saved to: $output_file"
    
    # Display the number of variables found
    var_count=$(jq length "$output_file" 2>/dev/null || echo "unknown")
    echo "✓ Found $var_count environment variables"
    
    echo
    echo "To view the contents:"
    echo "  cat $output_file | jq ."
else
    echo "✗ Error occurred while fetching environment variables"
    exit 1
fi
