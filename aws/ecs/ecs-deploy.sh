#!/bin/bash

# AWS ECS Deployment Utility
# This script helps to force new deployments of ECS services

set -e

# Colors for better output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print header with color
echo_header() {
  echo -e "${BLUE}========== $1 ==========${NC}"
}

# Print success message
echo_success() {
  echo -e "${GREEN}$1${NC}"
}

# Print warning/important message
echo_warning() {
  echo -e "${YELLOW}$1${NC}"
}

# Print error message
echo_error() {
  echo -e "${RED}$1${NC}"
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
  echo_error "AWS CLI not found. Please install it first."
  exit 1
fi

# Check for jq
if ! command -v jq &> /dev/null; then
  echo_error "jq is not installed. Please install it to use this script."
  exit 1
fi

# List available clusters
list_clusters() {
  echo_header "AVAILABLE ECS CLUSTERS"
  aws ecs list-clusters --output text | awk -F/ '{print NR")", $NF}'
  echo
}

# List services in a cluster
list_services() {
  local cluster_name=$1
  echo_header "SERVICES IN CLUSTER: $cluster_name"
  
  # Get all services in the cluster
  services=$(aws ecs list-services --cluster "$cluster_name" --output json)
  service_count=$(echo "$services" | jq -r '.serviceArns | length')
  
  if [ "$service_count" -eq 0 ]; then
    echo "No services found in this cluster."
    return 1
  fi
  
  # Extract service names
  service_arns=$(echo "$services" | jq -r '.serviceArns[]')
  
  # Display services with index numbers
  echo "$service_arns" | awk -F/ '{print $NF}' | nl -w3 -s') '
  echo
  
  return 0
}

# Get service details
get_service_details() {
  local cluster_name=$1
  local service_name=$2
  
  # Get service details
  echo "Fetching service details..."
  service_details=$(aws ecs describe-services --cluster "$cluster_name" --services "$service_name" --output json)
  
  # Extract and display service information
  echo_header "SERVICE DETAILS: $service_name"
  
  # Task definition
  task_def=$(echo "$service_details" | jq -r '.services[0].taskDefinition' | awk -F/ '{print $NF}')
  echo "Task Definition: $task_def"
  
  # Deployments
  deployments=$(echo "$service_details" | jq -r '.services[0].deployments')
  deployment_count=$(echo "$deployments" | jq 'length')
  
  echo "Active Deployments: $deployment_count"
  echo
  
  for (( i=0; i<$deployment_count; i++ )); do
    status=$(echo "$deployments" | jq -r ".[$i].status")
    task_def=$(echo "$deployments" | jq -r ".[$i].taskDefinition" | awk -F/ '{print $NF}')
    desired=$(echo "$deployments" | jq -r ".[$i].desiredCount")
    running=$(echo "$deployments" | jq -r ".[$i].runningCount")
    pending=$(echo "$deployments" | jq -r ".[$i].pendingCount")
    created=$(echo "$deployments" | jq -r ".[$i].createdAt")
    updated=$(echo "$deployments" | jq -r ".[$i].updatedAt")
    
    # Convert timestamps to human-readable format
    created_date=$(date -d "@$(echo $created | cut -d. -f1)" '+%Y-%m-%d %H:%M:%S')
    updated_date=$(date -d "@$(echo $updated | cut -d. -f1)" '+%Y-%m-%d %H:%M:%S')
    
    echo "Deployment $((i+1)):"
    echo "  Status: $status"
    echo "  Task Definition: $task_def"
    echo "  Desired Count: $desired"
    echo "  Running Count: $running"
    echo "  Pending Count: $pending"
    echo "  Created: $created_date"
    echo "  Updated: $updated_date"
    echo
  done
  
  # Events
  echo "Recent Events:"
  echo "$service_details" | jq -r '.services[0].events[0:5] | .[] | " - \(.createdAt | todate): \(.message)"'
  echo
  
  return 0
}

# Force a new deployment
force_deployment() {
  local cluster_name=$1
  local service_name=$2
  
  echo_header "FORCE NEW DEPLOYMENT: $service_name"
  
  # Get current service details for reference
  get_service_details "$cluster_name" "$service_name"
  
  # Confirm before proceeding
  read -p "Are you sure you want to force a new deployment? (y/N): " confirm
  
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    return 1
  fi
  
  # Force new deployment
  echo "Forcing new deployment of service $service_name..."
  aws ecs update-service --cluster "$cluster_name" --service "$service_name" --force-new-deployment > /dev/null
  
  echo_success "Service redeployment initiated successfully."
  
  # Ask if user wants to monitor deployment
  read -p "Would you like to monitor the deployment progress? (y/N): " monitor
  
  if [[ "$monitor" =~ ^[Yy]$ ]]; then
    monitor_deployment "$cluster_name" "$service_name"
  fi
  
  return 0
}

# Update task count
update_task_count() {
  local cluster_name=$1
  local service_name=$2
  
  # Get current desired count
  service_details=$(aws ecs describe-services --cluster "$cluster_name" --services "$service_name" --output json)
  current_count=$(echo "$service_details" | jq -r '.services[0].desiredCount')
  
  echo_header "UPDATE TASK COUNT: $service_name"
  echo "Current desired task count: $current_count"
  echo
  
  # Ask for new count
  read -p "Enter new desired task count (0-100): " new_count
  
  # Validate input
  if ! [[ "$new_count" =~ ^[0-9]+$ ]] || [ "$new_count" -gt 100 ]; then
    echo_error "Invalid input. Please enter a number between 0 and 100."
    return 1
  fi
  
  # Confirm before proceeding
  echo_warning "This will change the desired task count from $current_count to $new_count."
  read -p "Are you sure you want to proceed? (y/N): " confirm
  
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    return 1
  fi
  
  # Update service
  echo "Updating desired task count for service $service_name..."
  aws ecs update-service --cluster "$cluster_name" --service "$service_name" --desired-count "$new_count" > /dev/null
  
  echo_success "Service updated successfully. Desired task count is now $new_count."
  
  # Ask if user wants to monitor deployment
  read -p "Would you like to monitor the deployment progress? (y/N): " monitor
  
  if [[ "$monitor" =~ ^[Yy]$ ]]; then
    monitor_deployment "$cluster_name" "$service_name"
  fi
  
  return 0
}

# Monitor deployment progress
monitor_deployment() {
  local cluster_name=$1
  local service_name=$2
  local timeout=300  # seconds to monitor (5 minutes)
  local interval=10  # check every 10 seconds
  local elapsed=0
  
  echo_header "MONITORING DEPLOYMENT: $service_name"
  echo "Monitoring for ${timeout} seconds. Press Ctrl+C to stop monitoring."
  echo
  
  while [ $elapsed -lt $timeout ]; do
    # Get service details
    service_details=$(aws ecs describe-services --cluster "$cluster_name" --services "$service_name" --output json)
    
    # Extract deployment information
    primary_deployment=$(echo "$service_details" | jq -r '.services[0].deployments[] | select(.status=="PRIMARY")')
    desired=$(echo "$primary_deployment" | jq -r '.desiredCount')
    running=$(echo "$primary_deployment" | jq -r '.runningCount')
    pending=$(echo "$primary_deployment" | jq -r '.pendingCount')
    
    # Get the most recent event
    latest_event=$(echo "$service_details" | jq -r '.services[0].events[0].message')
    latest_event_time=$(echo "$service_details" | jq -r '.services[0].events[0].createdAt | todate')
    
    # Clear screen and show current status
    clear
    echo_header "DEPLOYMENT STATUS: $service_name"
    echo "Elapsed time: ${elapsed}s / ${timeout}s"
    echo
    echo "Tasks:"
    echo "  Desired: $desired"
    echo "  Running: $running"
    echo "  Pending: $pending"
    echo
    echo "Latest event (${latest_event_time}):"
    echo "  $latest_event"
    echo
    
    # Check if deployment is complete (all desired tasks are running and none are pending)
    if [ "$running" -eq "$desired" ] && [ "$pending" -eq 0 ]; then
      echo_success "Deployment appears to be complete! All desired tasks are running."
      echo
      
      # Get recent events for confirmation
      echo "Recent events:"
      echo "$service_details" | jq -r '.services[0].events[0:5] | .[] | " - \(.createdAt | todate): \(.message)"'
      echo
      
      # Ask if the user wants to continue monitoring
      read -t 1 -n 1 -p "Deployment appears complete. Press any key to exit monitoring, or wait to continue..." continue_key || true
      
      if [ -n "$continue_key" ]; then
        echo
        echo "Exiting monitoring."
        return 0
      fi
    fi
    
    sleep $interval
    elapsed=$((elapsed + interval))
  done
  
  echo_warning "Monitoring timeout reached. The deployment may still be in progress."
  echo "Please check the service status manually."
  
  return 0
}

# Deploy with a different task definition
deploy_with_task_def() {
  local cluster_name=$1
  local service_name=$2
  
  echo_header "DEPLOY WITH DIFFERENT TASK DEFINITION: $service_name"
  
  # Get current task definition
  service_details=$(aws ecs describe-services --cluster "$cluster_name" --services "$service_name" --output json)
  current_task_def=$(echo "$service_details" | jq -r '.services[0].taskDefinition')
  current_task_def_short=$(echo "$current_task_def" | awk -F/ '{print $NF}')
  
  echo "Current task definition: $current_task_def_short"
  echo
  
  # List recent task definitions
  echo "Fetching recent task definitions..."
  # Extract the task family name (without revision)
  task_family=$(echo "$current_task_def_short" | cut -d':' -f1)
  
  task_defs=$(aws ecs list-task-definitions --family-prefix "$task_family" --sort DESC --output json)
  task_def_arns=$(echo "$task_defs" | jq -r '.taskDefinitionArns[]' | head -10)
  
  if [ -z "$task_def_arns" ]; then
    echo_error "No task definitions found for family: $task_family"
    return 1
  fi
  
  echo_header "RECENT TASK DEFINITIONS"
  echo "$task_def_arns" | awk -F/ '{print NR")", $NF}'
  echo
  
  # Ask user to select a task definition
  read -p "Select a task definition (number) or press 'b' to go back, 'q' to quit: " task_def_selection
  
  if [[ "$task_def_selection" == "q" ]]; then
    echo "Exiting."
    exit 0
  fi
  
  if [[ "$task_def_selection" == "b" ]]; then
    return 1
  fi
  
  # Get the selected task definition
  selected_task_def=$(echo "$task_def_arns" | sed -n "${task_def_selection}p")
  selected_task_def_short=$(echo "$selected_task_def" | awk -F/ '{print $NF}')
  
  if [ -z "$selected_task_def" ]; then
    echo_error "Invalid selection. Please try again."
    return 1
  fi
  
  echo_success "Selected task definition: $selected_task_def_short"
  echo
  
  # Confirm before proceeding
  echo_warning "This will update the service to use task definition: $selected_task_def_short"
  read -p "Are you sure you want to proceed? (y/N): " confirm
  
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    return 1
  fi
  
  # Update service with new task definition
  echo "Updating service $service_name with task definition $selected_task_def_short..."
  aws ecs update-service --cluster "$cluster_name" --service "$service_name" --task-definition "$selected_task_def_short" > /dev/null
  
  echo_success "Service updated successfully with task definition: $selected_task_def_short"
  
  # Ask if user wants to monitor deployment
  read -p "Would you like to monitor the deployment progress? (y/N): " monitor
  
  if [[ "$monitor" =~ ^[Yy]$ ]]; then
    monitor_deployment "$cluster_name" "$service_name"
  fi
  
  return 0
}

# Main menu function
main_menu() {
  echo_header "MAIN MENU"
  echo "1) Force new deployment (no changes)"
  echo "2) Deploy with different task definition"
  echo "3) Update task count"
  echo "4) View service details"
  echo
  
  read -p "Select an option (1-4) or press 'q' to quit: " main_option
  
  if [[ "$main_option" == "q" ]]; then
    echo "Exiting."
    exit 0
  fi
  
  # List available clusters
  list_clusters
  
  # Ask user to select a cluster
  read -p "Select a cluster (number) or press 'b' to go back, 'q' to quit: " cluster_selection
  
  if [[ "$cluster_selection" == "q" ]]; then
    echo "Exiting."
    exit 0
  fi
  
  if [[ "$cluster_selection" == "b" ]]; then
    main_menu
    return
  fi
  
  # Get the selected cluster name
  selected_cluster=$(aws ecs list-clusters --output text | awk -F/ '{print $NF}' | sed -n "${cluster_selection}p")
  
  if [ -z "$selected_cluster" ]; then
    echo_error "Invalid selection. Please try again."
    main_menu
    return
  fi
  
  echo_success "Selected cluster: $selected_cluster"
  echo
  
  # List services in the cluster
  if ! list_services "$selected_cluster"; then
    echo "No services found. Returning to main menu."
    main_menu
    return
  fi
  
  # Ask user to select a service
  read -p "Select a service (number) or press 'b' to go back, 'q' to quit: " service_selection
  
  if [[ "$service_selection" == "q" ]]; then
    echo "Exiting."
    exit 0
  fi
  
  if [[ "$service_selection" == "b" ]]; then
    main_menu
    return
  fi
  
  # Get the selected service name
  services=$(aws ecs list-services --cluster "$selected_cluster" --output json)
  service_arns=$(echo "$services" | jq -r '.serviceArns[]')
  selected_service=$(echo "$service_arns" | sed -n "${service_selection}p" | awk -F/ '{print $NF}')
  
  if [ -z "$selected_service" ]; then
    echo_error "Invalid selection. Please try again."
    main_menu
    return
  fi
  
  echo_success "Selected service: $selected_service"
  echo
  
  # Perform the selected action
  case $main_option in
    1)
      # Force new deployment
      if ! force_deployment "$selected_cluster" "$selected_service"; then
        echo "Deployment cancelled. Returning to main menu."
        main_menu
        return
      fi
      ;;
    2)
      # Deploy with different task definition
      if ! deploy_with_task_def "$selected_cluster" "$selected_service"; then
        echo "Deployment cancelled. Returning to main menu."
        main_menu
        return
      fi
      ;;
    3)
      # Update task count
      if ! update_task_count "$selected_cluster" "$selected_service"; then
        echo "Update cancelled. Returning to main menu."
        main_menu
        return
      fi
      ;;
    4)
      # View service details
      get_service_details "$selected_cluster" "$selected_service"
      ;;
    *)
      echo_error "Invalid option. Please try again."
      main_menu
      return
      ;;
  esac
  
  # Return to main menu
  echo
  echo "Press Enter to return to main menu..."
  read
  main_menu
}

# Display welcome message
echo_header "AWS ECS DEPLOYMENT UTILITY"
echo "This script helps you deploy and manage ECS services."
echo_warning "Requirements:"
echo " - AWS CLI configured with appropriate permissions"
echo " - jq installed (for JSON parsing)"
echo
echo "Press Ctrl+C to exit at any time."
echo

# Start the main menu
main_menu