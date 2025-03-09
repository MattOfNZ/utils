#!/bin/bash

# AWS ECS CLI Helper
# This script helps to list ECS tasks and connect to them using ECS exec

set -e

# Colors for better output
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
  echo "AWS CLI not found. Please install it first."
  exit 1
fi

# List available clusters
list_clusters() {
  echo_header "AVAILABLE ECS CLUSTERS"
  aws ecs list-clusters --output text | awk -F/ '{print NR")", $NF}'
  echo
}

# List tasks in a specific cluster
list_tasks() {
  local cluster_name=$1
  echo_header "TASKS IN CLUSTER: $cluster_name"
  
  # Get all tasks in the cluster
  tasks=$(aws ecs list-tasks --cluster "$cluster_name" --output json)
  task_count=$(echo "$tasks" | jq -r '.taskArns | length')
  
  if [ "$task_count" -eq 0 ]; then
    echo "No tasks found in this cluster."
    return 1
  fi
  
  # Extract task IDs
  task_arns=$(echo "$tasks" | jq -r '.taskArns[]')
  
  # Get detailed task information
  task_details=$(aws ecs describe-tasks --cluster "$cluster_name" --tasks $task_arns --output json)
  
  # Display tasks with index numbers
  echo "$task_details" | jq -r '.tasks[] | "\(.taskArn | split("/") | .[-1]) - \(.group) - \(.lastStatus)"' | nl -w3 -s') '
  echo
  
  return 0
}

# Get containers for a specific task
get_containers() {
  local cluster_name=$1
  local task_id=$2
  
  # Get task details to extract container information
  task_details=$(aws ecs describe-tasks --cluster "$cluster_name" --tasks "$task_id" --output json)
  
  # Extract and display container names
  containers=$(echo "$task_details" | jq -r '.tasks[0].containers[] | "\(.name) (\(.lastStatus))"' | nl -w3 -s') ')
  
  if [ -z "$containers" ]; then
    echo "No containers found for this task."
    return 1
  fi
  
  echo_header "CONTAINERS IN TASK: $task_id"
  echo "$containers"
  echo
  
  # Get container count
  container_count=$(echo "$task_details" | jq -r '.tasks[0].containers | length')
  
  return 0
}

# Connect to a container using ECS exec
connect_to_container() {
  local cluster_name=$1
  local task_id=$2
  local container_name=$3
  
  echo_header "CONNECTING TO CONTAINER: $container_name"
  echo_warning "Executing: aws ecs execute-command --cluster $cluster_name --task $task_id --container $container_name --interactive --command \"/bin/sh\""
  echo
  
  # Check if execute-command is supported on the task
  support_check=$(aws ecs describe-tasks --cluster "$cluster_name" --tasks "$task_id" | jq -r '.tasks[0].enableExecuteCommand')
  
  if [ "$support_check" == "false" ]; then
    echo_warning "WARNING: This task may not have execute-command enabled."
    echo_warning "If connection fails, make sure your task definition and cluster have ECS Exec enabled."
    echo
  fi
  
  # Execute the command
  aws ecs execute-command \
    --cluster "$cluster_name" \
    --task "$task_id" \
    --container "$container_name" \
    --interactive \
    --command "/bin/sh"
}

# Main menu
main_menu() {
  # List available clusters
  list_clusters
  
  # Ask user to select a cluster
  read -p "Select a cluster (number) or press 'q' to quit: " cluster_selection
  
  if [[ "$cluster_selection" == "q" ]]; then
    echo "Exiting."
    exit 0
  fi
  
  # Get the selected cluster name
  selected_cluster=$(aws ecs list-clusters --output text | awk -F/ '{print $NF}' | sed -n "${cluster_selection}p")
  
  if [ -z "$selected_cluster" ]; then
    echo "Invalid selection. Please try again."
    main_menu
    return
  fi
  
  echo_success "Selected cluster: $selected_cluster"
  echo
  
  # List tasks in the selected cluster
  if ! list_tasks "$selected_cluster"; then
    echo "Returning to cluster selection."
    main_menu
    return
  fi
  
  # Ask user to select a task
  read -p "Select a task (number) or press 'b' to go back, 'q' to quit: " task_selection
  
  if [[ "$task_selection" == "q" ]]; then
    echo "Exiting."
    exit 0
  fi
  
  if [[ "$task_selection" == "b" ]]; then
    main_menu
    return
  fi
  
  # Get the selected task ID
  tasks=$(aws ecs list-tasks --cluster "$selected_cluster" --output json)
  task_arns=$(echo "$tasks" | jq -r '.taskArns[]')
  selected_task_id=$(echo "$task_arns" | sed -n "${task_selection}p" | awk -F/ '{print $NF}')
  
  if [ -z "$selected_task_id" ]; then
    echo "Invalid selection. Please try again."
    main_menu
    return
  fi
  
  echo_success "Selected task: $selected_task_id"
  echo
  
  # Get containers for the selected task
  if ! get_containers "$selected_cluster" "$selected_task_id"; then
    echo "Returning to cluster selection."
    main_menu
    return
  fi
  
  # Ask user to select a container
  read -p "Select a container (number) or press 'b' to go back, 'q' to quit: " container_selection
  
  if [[ "$container_selection" == "q" ]]; then
    echo "Exiting."
    exit 0
  fi
  
  if [[ "$container_selection" == "b" ]]; then
    main_menu
    return
  fi
  
  # Get the selected container name
  task_details=$(aws ecs describe-tasks --cluster "$selected_cluster" --tasks "$selected_task_id" --output json)
  selected_container=$(echo "$task_details" | jq -r ".tasks[0].containers[$(($container_selection-1))].name")
  
  if [ -z "$selected_container" ]; then
    echo "Invalid selection. Please try again."
    main_menu
    return
  fi
  
  echo_success "Selected container: $selected_container"
  echo
  
  # Connect to the selected container
  connect_to_container "$selected_cluster" "$selected_task_id" "$selected_container"
  
  # Return to main menu after connection ends
  echo
  echo_warning "Connection closed."
  echo
  main_menu
}

# Display welcome message
echo_header "AWS ECS CLI HELPER"
echo "This script helps you list and connect to ECS tasks using ECS exec."
echo_warning "Requirements:"
echo " - AWS CLI configured with appropriate permissions"
echo " - jq installed (for JSON parsing)"
echo " - ECS Exec enabled on your cluster and task definition"
echo

# Check for jq
if ! command -v jq &> /dev/null; then
  echo "jq is not installed. Please install it to use this script."
  exit 1
fi

# Start the main menu
main_menu