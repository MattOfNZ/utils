#!/bin/bash

# AWS ECS Log Viewer
# This script helps to view and filter CloudWatch logs for ECS tasks

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

# Check for jq
if ! command -v jq &> /dev/null; then
  echo "jq is not installed. Please install it to use this script."
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

# Get log information for a task
get_task_logs() {
  local cluster_name=$1
  local task_id=$2
  
  # Get task details to extract container information
  task_details=$(aws ecs describe-tasks --cluster "$cluster_name" --tasks "$task_id" --output json)
  
  # Extract task definition name
  task_def_arn=$(echo "$task_details" | jq -r '.tasks[0].taskDefinitionArn')
  task_def_name=$(echo "$task_def_arn" | awk -F/ '{print $NF}' | awk -F: '{print $1}')
  
  # Get container details
  containers=$(echo "$task_details" | jq -r '.tasks[0].containers[] | "\(.name)"')
  
  # Display containers with index numbers
  echo_header "CONTAINERS IN TASK: $task_id"
  echo "$containers" | nl -w3 -s') '
  echo
  
  # Ask user to select a container
  read -p "Select a container (number) or press 'b' to go back, 'q' to quit: " container_selection
  
  if [[ "$container_selection" == "q" ]]; then
    echo "Exiting."
    exit 0
  fi
  
  if [[ "$container_selection" == "b" ]]; then
    return 1
  fi
  
  # Get the selected container name
  selected_container=$(echo "$containers" | sed -n "${container_selection}p")
  
  if [ -z "$selected_container" ]; then
    echo "Invalid selection. Please try again."
    return 1
  fi
  
  echo_success "Selected container: $selected_container"
  echo
  
  # Construct log group name
  # Format is typically /ecs/{task-definition-name}
  log_group="/ecs/${task_def_name}"
  
  # Construct log stream name
  # Format is typically {container-name}/{task-definition-name}/{task-id}
  log_stream="${selected_container}/${task_def_name}/${task_id}"
  
  echo_header "LOG INFORMATION"
  echo "Log Group: $log_group"
  echo "Log Stream: $log_stream"
  echo
  
  # Check if log group exists
  if ! aws logs describe-log-groups --log-group-name-prefix "$log_group" | jq -r '.logGroups[].logGroupName' | grep -q "^$log_group$"; then
    echo_warning "Log group not found: $log_group"
    echo "Please check if CloudWatch logs are enabled for this task."
    return 1
  fi
  
  # Check if log stream exists
  if ! aws logs describe-log-streams --log-group-name "$log_group" --log-stream-name-prefix "$log_stream" | jq -r '.logStreams[].logStreamName' | grep -q "^$log_stream$"; then
    echo_warning "Log stream not found: $log_stream"
    echo "Please check if the container is generating logs."
    return 1
  fi
  
  # Ask for log viewing options
  echo "How would you like to view logs?"
  echo "1) View recent logs (last 100 entries)"
  echo "2) Tail logs (follow in real-time)"
  echo "3) Search logs (grep)"
  echo
  
  read -p "Select an option (1-3) or press 'b' to go back, 'q' to quit: " log_option
  
  if [[ "$log_option" == "q" ]]; then
    echo "Exiting."
    exit 0
  fi
  
  if [[ "$log_option" == "b" ]]; then
    return 1
  fi
  
  case $log_option in
    1)
      view_recent_logs "$log_group" "$log_stream"
      ;;
    2)
      tail_logs "$log_group" "$log_stream"
      ;;
    3)
      search_logs "$log_group" "$log_stream"
      ;;
    *)
      echo "Invalid option. Please try again."
      return 1
      ;;
  esac
  
  return 0
}

# View recent logs
view_recent_logs() {
  local log_group=$1
  local log_stream=$2
  
  echo_header "VIEWING RECENT LOGS"
  echo "Log Group: $log_group"
  echo "Log Stream: $log_stream"
  echo
  
  # Get recent logs
  aws logs get-log-events \
    --log-group-name "$log_group" \
    --log-stream-name "$log_stream" \
    --limit 100 \
    --output json | jq -r '.events[] | "\(.timestamp | todate) - \(.message)"'
  
  echo
  read -p "Press Enter to continue..."
  return 0
}

# Tail logs in real-time
tail_logs() {
  local log_group=$1
  local log_stream=$2
  
  echo_header "TAILING LOGS (CTRL+C TO EXIT)"
  echo "Log Group: $log_group"
  echo "Log Stream: $log_stream"
  echo
  
  # Get the most recent timestamp
  latest_timestamp=$(aws logs get-log-events \
    --log-group-name "$log_group" \
    --log-stream-name "$log_stream" \
    --limit 1 \
    --start-from-head false \
    --output json | jq -r '.events[0].timestamp')
  
  if [ -z "$latest_timestamp" ] || [ "$latest_timestamp" == "null" ]; then
    latest_timestamp=0
  fi
  
  echo "Starting to tail logs from timestamp: $(date -d @$((latest_timestamp/1000)))"
  echo
  
  # Continuously get logs
  while true; do
    new_logs=$(aws logs get-log-events \
      --log-group-name "$log_group" \
      --log-stream-name "$log_stream" \
      --start-time $((latest_timestamp + 1)) \
      --output json)
    
    # Display new log events
    events=$(echo "$new_logs" | jq -r '.events[]')
    if [ -n "$events" ]; then
      echo "$events" | jq -r '"\(.timestamp | todate) - \(.message)"'
      
      # Update the latest timestamp
      new_latest=$(echo "$new_logs" | jq -r '.events[-1].timestamp')
      if [ -n "$new_latest" ] && [ "$new_latest" != "null" ]; then
        latest_timestamp=$new_latest
      fi
    fi
    
    # Sleep for a short time before checking for new logs
    sleep 2
  done
}

# Search logs for a pattern
search_logs() {
  local log_group=$1
  local log_stream=$2
  
  echo_header "SEARCHING LOGS"
  echo "Log Group: $log_group"
  echo "Log Stream: $log_stream"
  echo
  
  read -p "Enter search pattern: " search_pattern
  
  if [ -z "$search_pattern" ]; then
    echo "Search pattern cannot be empty."
    return 1
  fi
  
  echo
  echo "Searching for: $search_pattern"
  echo
  
  # Use filter-log-events with a filter pattern
  aws logs get-log-events \
    --log-group-name "$log_group" \
    --log-stream-name "$log_stream" \
    --limit 1000 \
    --output json | \
    jq -r --arg pattern "$search_pattern" '.events[] | select(.message | contains($pattern)) | "\(.timestamp | todate) - \(.message)"'
  
  echo
  read -p "Press Enter to continue..."
  return 0
}

# Main function
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
  
  # Get logs for the selected task
  if ! get_task_logs "$selected_cluster" "$selected_task_id"; then
    echo "Returning to task selection."
    main_menu
    return
  fi
  
  # Return to main menu
  echo
  main_menu
}

# Display welcome message
echo_header "AWS ECS LOG VIEWER"
echo "This script helps you view and filter CloudWatch logs for ECS tasks."
echo_warning "Requirements:"
echo " - AWS CLI configured with appropriate permissions"
echo " - jq installed (for JSON parsing)"
echo " - CloudWatch logs enabled for your ECS tasks"
echo
echo "Press Ctrl+C to exit at any time."
echo

# Start the main menu
main_menu