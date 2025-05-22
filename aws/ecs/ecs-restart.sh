#!/bin/bash

# AWS ECS Task Restart Utility
# This script helps to restart ECS tasks

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

# List tasks in a specific cluster or service
list_tasks() {
  local cluster_name=$1
  local service_name=$2
  
  if [ -z "$service_name" ]; then
    echo_header "TASKS IN CLUSTER: $cluster_name"
    task_filter=""
  else
    echo_header "TASKS IN SERVICE: $service_name"
    task_filter="--service-name $service_name"
  fi
  
  # Get all tasks in the cluster/service
  tasks=$(aws ecs list-tasks --cluster "$cluster_name" $task_filter --output json)
  task_count=$(echo "$tasks" | jq -r '.taskArns | length')
  
  if [ "$task_count" -eq 0 ]; then
    echo "No tasks found."
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

# Restart a specific task
restart_task() {
  local cluster_name=$1
  local task_id=$2
  
  echo_header "RESTARTING TASK: $task_id"
  
  # Get task details
  task_details=$(aws ecs describe-tasks --cluster "$cluster_name" --tasks "$task_id" --output json)
  
  # Extract task information
  task_def_arn=$(echo "$task_details" | jq -r '.tasks[0].taskDefinitionArn')
  task_group=$(echo "$task_details" | jq -r '.tasks[0].group')
  
  # Check if this is a service task or a standalone task
  is_service_task=false
  service_name=""
  
  if [[ "$task_group" == "service:"* ]]; then
    is_service_task=true
    service_name=$(echo "$task_group" | sed 's/service://')
    echo_warning "This task belongs to service: $service_name"
    echo_warning "Stopping this task will cause the service scheduler to start a replacement task."
  else
    echo_warning "This is a standalone task. After stopping, you'll need to start a new task manually."
  fi
  
  # Confirm before proceeding
  read -p "Are you sure you want to restart this task? (y/N): " confirm
  
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    return 1
  fi
  
  # Stop the task
  echo "Stopping task $task_id..."
  aws ecs stop-task --cluster "$cluster_name" --task "$task_id" > /dev/null
  
  echo_success "Task stop request sent successfully."
  
  if [ "$is_service_task" = true ]; then
    echo "The service scheduler will automatically start a replacement task."
    echo "Monitoring service for new tasks..."
    
    # Wait for a short period to allow the service to start a new task
    sleep 5
    
    # Monitor the service for new tasks
    monitor_service_tasks "$cluster_name" "$service_name"
  else
    # For standalone tasks, offer to run a new task with the same task definition
    echo
    read -p "Would you like to run a new task with the same task definition? (y/N): " run_new
    
    if [[ "$run_new" =~ ^[Yy]$ ]]; then
      run_new_task "$cluster_name" "$task_def_arn"
    else
      echo "No new task will be started."
    fi
  fi
  
  return 0
}

# Monitor a service for new tasks after stopping a task
monitor_service_tasks() {
  local cluster_name=$1
  local service_name=$2
  local timeout=60  # seconds to wait for a new task
  local interval=5  # check every 5 seconds
  local elapsed=0
  
  echo
  echo "Monitoring service for new tasks (timeout: ${timeout}s)..."
  
  while [ $elapsed -lt $timeout ]; do
    # Get current tasks in the service
    current_tasks=$(aws ecs list-tasks --cluster "$cluster_name" --service-name "$service_name" --output json)
    task_count=$(echo "$current_tasks" | jq -r '.taskArns | length')
    
    if [ "$task_count" -gt 0 ]; then
      # Get task details to check status
      task_arns=$(echo "$current_tasks" | jq -r '.taskArns[]')
      task_details=$(aws ecs describe-tasks --cluster "$cluster_name" --tasks $task_arns --output json)
      
      # Check if any task is in RUNNING state
      running_tasks=$(echo "$task_details" | jq -r '.tasks[] | select(.lastStatus=="RUNNING") | .taskArn')
      
      if [ -n "$running_tasks" ]; then
        echo_success "New task(s) detected and running:"
        echo "$task_details" | jq -r '.tasks[] | select(.lastStatus=="RUNNING") | "\(.taskArn | split("/") | .[-1]) - \(.lastStatus)"'
        return 0
      fi
      
      # Check if any task is in PENDING state
      pending_tasks=$(echo "$task_details" | jq -r '.tasks[] | select(.lastStatus=="PENDING") | .taskArn')
      
      if [ -n "$pending_tasks" ]; then
        echo "New task(s) detected but still pending:"
        echo "$task_details" | jq -r '.tasks[] | select(.lastStatus=="PENDING") | "\(.taskArn | split("/") | .[-1]) - \(.lastStatus)"'
      else
        echo "Waiting for new tasks to be created..."
      fi
    else
      echo "No tasks currently in the service. Waiting for new tasks..."
    fi
    
    sleep $interval
    elapsed=$((elapsed + interval))
    echo "Elapsed time: ${elapsed}s / ${timeout}s"
  done
  
  echo_warning "Timeout reached while waiting for new tasks."
  echo "Please check the service status manually."
  
  return 1
}

# Run a new standalone task
run_new_task() {
  local cluster_name=$1
  local task_def_arn=$2
  
  echo
  echo_header "RUNNING NEW TASK"
  echo "Cluster: $cluster_name"
  echo "Task Definition: $(echo $task_def_arn | awk -F/ '{print $NF}')"
  
  # Run a new task
  echo "Starting new task..."
  result=$(aws ecs run-task --cluster "$cluster_name" --task-definition "$task_def_arn" --count 1 --output json)
  
  # Check if the task was started successfully
  task_arn=$(echo "$result" | jq -r '.tasks[0].taskArn')
  
  if [ -n "$task_arn" ] && [ "$task_arn" != "null" ]; then
    task_id=$(echo "$task_arn" | awk -F/ '{print $NF}')
    echo_success "New task started successfully: $task_id"
  else
    error=$(echo "$result" | jq -r '.failures[0].reason')
    echo_error "Failed to start new task: $error"
    return 1
  fi
  
  return 0
}

# Restart all tasks in a service
restart_service() {
  local cluster_name=$1
  local service_name=$2
  
  echo_header "RESTARTING SERVICE: $service_name"
  
  # Confirm before proceeding
  read -p "Are you sure you want to restart all tasks in this service? (y/N): " confirm
  
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    return 1
  fi
  
  # Option 1: Force a new deployment
  echo "Choose restart method:"
  echo "1) Force new deployment (recommended, zero downtime)"
  echo "2) Stop all tasks (may cause brief downtime)"
  echo
  
  read -p "Select option (1-2): " restart_option
  
  case $restart_option in
    1)
      # Force a new deployment
      echo "Forcing new deployment of service $service_name..."
      aws ecs update-service --cluster "$cluster_name" --service "$service_name" --force-new-deployment > /dev/null
      echo_success "Service redeployment initiated successfully."
      ;;
    2)
      # Stop all tasks in the service
      echo "Stopping all tasks in service $service_name..."
      
      # Get all tasks in the service
      tasks=$(aws ecs list-tasks --cluster "$cluster_name" --service-name "$service_name" --output json)
      task_arns=$(echo "$tasks" | jq -r '.taskArns[]')
      
      if [ -z "$task_arns" ]; then
        echo_warning "No tasks found in the service."
        return 1
      fi
      
      # Stop each task
      for task_arn in $task_arns; do
        task_id=$(echo "$task_arn" | awk -F/ '{print $NF}')
        echo "Stopping task $task_id..."
        aws ecs stop-task --cluster "$cluster_name" --task "$task_id" > /dev/null
      done
      
      echo_success "All tasks stopped successfully."
      echo "The service scheduler will automatically start replacement tasks."
      echo "Monitoring service for new tasks..."
      
      # Wait for a short period to allow the service to start new tasks
      sleep 5
      
      # Monitor the service for new tasks
      monitor_service_tasks "$cluster_name" "$service_name"
      ;;
    *)
      echo_error "Invalid option. Operation cancelled."
      return 1
      ;;
  esac
  
  return 0
}

# Main menu function
main_menu() {
  echo_header "MAIN MENU"
  echo "1) Restart individual task"
  echo "2) Restart all tasks in a service"
  echo
  
  read -p "Select an option (1-2) or press 'q' to quit: " main_option
  
  if [[ "$main_option" == "q" ]]; then
    echo "Exiting."
    exit 0
  fi
  
  case $main_option in
    1)
      restart_task_menu
      ;;
    2)
      restart_service_menu
      ;;
    *)
      echo_error "Invalid option. Please try again."
      main_menu
      ;;
  esac
}

# Menu for restarting individual tasks
restart_task_menu() {
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
    restart_task_menu
    return
  fi
  
  echo_success "Selected cluster: $selected_cluster"
  echo
  
  # Ask user if they want to filter by service
  echo "Do you want to view tasks:"
  echo "1) From all services in the cluster"
  echo "2) From a specific service"
  echo
  
  read -p "Select an option (1-2) or press 'b' to go back, 'q' to quit: " filter_option
  
  if [[ "$filter_option" == "q" ]]; then
    echo "Exiting."
    exit 0
  fi
  
  if [[ "$filter_option" == "b" ]]; then
    restart_task_menu
    return
  fi
  
  selected_service=""
  
  if [[ "$filter_option" == "2" ]]; then
    # List services in the cluster
    if ! list_services "$selected_cluster"; then
      echo "Returning to cluster selection."
      restart_task_menu
      return
    fi
    
    # Ask user to select a service
    read -p "Select a service (number) or press 'b' to go back, 'q' to quit: " service_selection
    
    if [[ "$service_selection" == "q" ]]; then
      echo "Exiting."
      exit 0
    fi
    
    if [[ "$service_selection" == "b" ]]; then
      restart_task_menu
      return
    fi
    
    # Get the selected service name
    services=$(aws ecs list-services --cluster "$selected_cluster" --output json)
    service_arns=$(echo "$services" | jq -r '.serviceArns[]')
    selected_service=$(echo "$service_arns" | sed -n "${service_selection}p" | awk -F/ '{print $NF}')
    
    if [ -z "$selected_service" ]; then
      echo_error "Invalid selection. Please try again."
      restart_task_menu
      return
    fi
    
    echo_success "Selected service: $selected_service"
    echo
  fi
  
  # List tasks based on selection
  if ! list_tasks "$selected_cluster" "$selected_service"; then
    echo "No tasks found. Returning to main menu."
    main_menu
    return
  fi
  
  # Ask user to select a task
  read -p "Select a task to restart (number) or press 'b' to go back, 'q' to quit: " task_selection
  
  if [[ "$task_selection" == "q" ]]; then
    echo "Exiting."
    exit 0
  fi
  
  if [[ "$task_selection" == "b" ]]; then
    restart_task_menu
    return
  fi
  
  # Get the selected task ID
  if [ -z "$selected_service" ]; then
    tasks=$(aws ecs list-tasks --cluster "$selected_cluster" --output json)
  else
    tasks=$(aws ecs list-tasks --cluster "$selected_cluster" --service-name "$selected_service" --output json)
  fi
  
  task_arns=$(echo "$tasks" | jq -r '.taskArns[]')
  selected_task_id=$(echo "$task_arns" | sed -n "${task_selection}p" | awk -F/ '{print $NF}')
  
  if [ -z "$selected_task_id" ]; then
    echo_error "Invalid selection. Please try again."
    restart_task_menu
    return
  fi
  
  # Restart the selected task
  if ! restart_task "$selected_cluster" "$selected_task_id"; then
    echo "Task restart cancelled. Returning to main menu."
    main_menu
    return
  fi
  
  # Return to main menu
  echo
  echo "Press Enter to return to main menu..."
  read
  main_menu
}

# Menu for restarting services
restart_service_menu() {
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
    restart_service_menu
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
    restart_service_menu
    return
  fi
  
  # Get the selected service name
  services=$(aws ecs list-services --cluster "$selected_cluster" --output json)
  service_arns=$(echo "$services" | jq -r '.serviceArns[]')
  selected_service=$(echo "$service_arns" | sed -n "${service_selection}p" | awk -F/ '{print $NF}')
  
  if [ -z "$selected_service" ]; then
    echo_error "Invalid selection. Please try again."
    restart_service_menu
    return
  fi
  
  echo_success "Selected service: $selected_service"
  echo
  
  # Restart the selected service
  if ! restart_service "$selected_cluster" "$selected_service"; then
    echo "Service restart cancelled. Returning to main menu."
    main_menu
    return
  fi
  
  # Return to main menu
  echo
  echo "Press Enter to return to main menu..."
  read
  main_menu
}

# Display welcome message
echo_header "AWS ECS TASK RESTART UTILITY"
echo "This script helps you restart ECS tasks and services."
echo_warning "Requirements:"
echo " - AWS CLI configured with appropriate permissions"
echo " - jq installed (for JSON parsing)"
echo
echo "Press Ctrl+C to exit at any time."
echo

# Start the main menu
main_menu