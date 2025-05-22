#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
ECS Status Utility
-----------------
A script for retrieving detailed status information about ECS clusters, services, and tasks.
Uses the AWS SDK for Python (boto3) with only standard library dependencies.

Requirements:
- AWS CLI configured with appropriate permissions
- boto3 (which is preinstalled in AWS CloudShell)
"""

import argparse
import boto3
import datetime
import json
import os
import re
import sys
import time
from collections import defaultdict

# ANSI color codes for terminal output
COLORS = {
    'BLUE': '\033[0;34m',
    'GREEN': '\033[0;32m',
    'YELLOW': '\033[1;33m',
    'RED': '\033[0;31m',
    'BOLD': '\033[1m',
    'NC': '\033[0m'  # No Color
}

def print_header(text):
    """Print a header with color."""
    print(f"{COLORS['BLUE']}========== {text} =========={COLORS['NC']}")

def print_success(text):
    """Print a success message."""
    print(f"{COLORS['GREEN']}{text}{COLORS['NC']}")

def print_warning(text):
    """Print a warning message."""
    print(f"{COLORS['YELLOW']}{text}{COLORS['NC']}")

def print_error(text):
    """Print an error message."""
    print(f"{COLORS['RED']}{text}{COLORS['NC']}")

def print_bold(text):
    """Print text in bold."""
    print(f"{COLORS['BOLD']}{text}{COLORS['NC']}")

def format_timestamp(timestamp):
    """Format a timestamp to a human-readable string."""
    if not timestamp:
        return "N/A"
    
    if isinstance(timestamp, (int, float)):
        # Convert epoch to datetime
        dt = datetime.datetime.fromtimestamp(timestamp)
    else:
        dt = timestamp
    
    return dt.strftime('%Y-%m-%d %H:%M:%S')

def truncate_string(s, max_length=50):
    """Truncate a string to a maximum length and add ellipsis."""
    if len(s) <= max_length:
        return s
    return s[:max_length-3] + '...'

def get_clusters(ecs_client):
    """List all ECS clusters."""
    clusters = []
    next_token = None
    
    while True:
        if next_token:
            response = ecs_client.list_clusters(nextToken=next_token)
        else:
            response = ecs_client.list_clusters()
        
        clusters.extend(response['clusterArns'])
        
        if 'nextToken' in response:
            next_token = response['nextToken']
        else:
            break
    
    return clusters

def get_services(ecs_client, cluster_arn):
    """List all services in a cluster."""
    services = []
    next_token = None
    
    while True:
        if next_token:
            response = ecs_client.list_services(cluster=cluster_arn, nextToken=next_token)
        else:
            response = ecs_client.list_services(cluster=cluster_arn)
        
        services.extend(response['serviceArns'])
        
        if 'nextToken' in response:
            next_token = response['nextToken']
        else:
            break
    
    return services

def get_tasks(ecs_client, cluster_arn, service_arn=None):
    """List all tasks in a cluster, optionally filtered by service."""
    tasks = []
    next_token = None
    
    while True:
        if service_arn:
            if next_token:
                response = ecs_client.list_tasks(cluster=cluster_arn, serviceName=service_arn, nextToken=next_token)
            else:
                response = ecs_client.list_tasks(cluster=cluster_arn, serviceName=service_arn)
        else:
            if next_token:
                response = ecs_client.list_tasks(cluster=cluster_arn, nextToken=next_token)
            else:
                response = ecs_client.list_tasks(cluster=cluster_arn)
        
        tasks.extend(response['taskArns'])
        
        if 'nextToken' in response:
            next_token = response['nextToken']
        else:
            break
    
    return tasks

def get_task_details(ecs_client, cluster_arn, task_arns):
    """Get detailed information about tasks."""
    if not task_arns:
        return []
    
    # AWS API limit: describe_tasks can only handle 100 tasks at a time
    task_chunks = [task_arns[i:i+100] for i in range(0, len(task_arns), 100)]
    all_tasks = []
    
    for chunk in task_chunks:
        response = ecs_client.describe_tasks(cluster=cluster_arn, tasks=chunk)
        all_tasks.extend(response['tasks'])
    
    return all_tasks

def get_service_details(ecs_client, cluster_arn, service_arns):
    """Get detailed information about services."""
    if not service_arns:
        return []
    
    # AWS API limit: describe_services can only handle 10 services at a time
    service_chunks = [service_arns[i:i+10] for i in range(0, len(service_arns), 10)]
    all_services = []
    
    for chunk in service_chunks:
        response = ecs_client.describe_services(cluster=cluster_arn, services=chunk)
        all_services.extend(response['services'])
    
    return all_services

def get_cluster_details(ecs_client, cluster_arns):
    """Get detailed information about clusters."""
    if not cluster_arns:
        return []
    
    # AWS API limit: describe_clusters can handle multiple clusters
    response = ecs_client.describe_clusters(clusters=cluster_arns, include=['STATISTICS'])
    return response['clusters']

def get_task_definition_details(ecs_client, task_definition_arn):
    """Get detailed information about a task definition."""
    response = ecs_client.describe_task_definition(taskDefinition=task_definition_arn)
    return response['taskDefinition']

def print_cluster_summary(cluster):
    """Print a summary of a cluster."""
    print_bold(f"Cluster: {cluster['clusterName']}")
    print(f"ARN: {cluster['clusterArn']}")
    print(f"Status: {cluster['status']}")
    print(f"Running Tasks: {cluster.get('runningTasksCount', 'N/A')}")
    print(f"Pending Tasks: {cluster.get('pendingTasksCount', 'N/A')}")
    print(f"Active Services: {cluster.get('activeServicesCount', 'N/A')}")
    print(f"Container Instances: {cluster.get('registeredContainerInstancesCount', 'N/A')}")
    
    if 'statistics' in cluster and cluster['statistics']:
        print("Statistics:")
        for stat in cluster['statistics']:
            print(f"  {stat['name']}: {stat['value']}")
    
    print()

def print_service_summary(service):
    """Print a summary of a service."""
    service_name = service['serviceName']
    print_bold(f"Service: {service_name}")
    
    # Task definition
    task_def = service['taskDefinition'].split('/')[-1]
    print(f"Task Definition: {task_def}")
    
    # Launch type
    launch_type = service.get('launchType', 'N/A')
    print(f"Launch Type: {launch_type}")
    
    # Task counts
    desired = service['desiredCount']
    running = service['runningCount']
    pending = service['pendingCount']
    print(f"Tasks: {running} running, {pending} pending, {desired} desired")
    
    # Deployments
    if 'deployments' in service and service['deployments']:
        print("Deployments:")
        for deployment in service['deployments']:
            status = deployment['status']
            created = format_timestamp(deployment['createdAt'])
            updated = format_timestamp(deployment['updatedAt'])
            task_def = deployment['taskDefinition'].split('/')[-1]
            d_desired = deployment['desiredCount']
            d_running = deployment['runningCount']
            d_pending = deployment['pendingCount']
            
            print(f"  {status}: {d_running}/{d_desired} running, {d_pending} pending")
            print(f"    Task Definition: {task_def}")
            print(f"    Created: {created}, Updated: {updated}")
    
    # Events (most recent first)
    if 'events' in service and service['events']:
        print("Recent Events:")
        for event in service['events'][:3]:  # Show 3 most recent
            timestamp = format_timestamp(event['createdAt'])
            message = truncate_string(event['message'], 80)
            print(f"  {timestamp}: {message}")
    
    print()

def print_task_summary(task):
    """Print a summary of a task."""
    task_id = task['taskArn'].split('/')[-1]
    print_bold(f"Task: {task_id}")
    
    # Basic info
    group = task.get('group', 'N/A')
    if group.startswith('service:'):
        group = f"Service: {group[8:]}"
    print(f"Group: {group}")
    print(f"Status: {task['lastStatus']}")
    
    # Task definition
    task_def = task['taskDefinition'].split('/')[-1]
    print(f"Task Definition: {task_def}")
    
    # Launch type
    launch_type = task.get('launchType', 'N/A')
    print(f"Launch Type: {launch_type}")
    
    # Timestamps
    if 'createdAt' in task:
        print(f"Created: {format_timestamp(task['createdAt'])}")
    if 'startedAt' in task:
        print(f"Started: {format_timestamp(task['startedAt'])}")
    if 'stoppedAt' in task:
        print(f"Stopped: {format_timestamp(task['stoppedAt'])}")
        if 'stoppedReason' in task:
            print(f"Stop Reason: {task['stoppedReason']}")
    
    # Containers
    if 'containers' in task and task['containers']:
        print("Containers:")
        for container in task['containers']:
            name = container['name']
            status = container['lastStatus']
            
            if status == 'RUNNING':
                status_color = COLORS['GREEN']
            elif status == 'PENDING':
                status_color = COLORS['YELLOW']
            elif status == 'STOPPED':
                status_color = COLORS['RED']
            else:
                status_color = COLORS['NC']
            
            print(f"  {name}: {status_color}{status}{COLORS['NC']}")
            
            if 'exitCode' in container:
                print(f"    Exit Code: {container['exitCode']}")
            if 'reason' in container:
                print(f"    Reason: {container['reason']}")
            
            # Health check
            if 'healthStatus' in container:
                health = container['healthStatus']
                if health == 'HEALTHY':
                    health_color = COLORS['GREEN']
                elif health == 'UNHEALTHY':
                    health_color = COLORS['RED']
                else:
                    health_color = COLORS['YELLOW']
                
                print(f"    Health: {health_color}{health}{COLORS['NC']}")
    
    print()

def get_logs_command(cluster_name, task_id, container_name):
    """Generate a command to view the logs for a container."""
    return f"aws logs get-log-events --log-group-name /ecs/{container_name} --log-stream-name {container_name}/{task_id}"

def list_clusters_menu(ecs_client):
    """Display a menu of clusters and prompt for selection."""
    cluster_arns = get_clusters(ecs_client)
    
    if not cluster_arns:
        print_warning("No clusters found.")
        return None
    
    print_header("AVAILABLE ECS CLUSTERS")
    
    clusters_list = []
    for i, arn in enumerate(cluster_arns, 1):
        cluster_name = arn.split('/')[-1]
        clusters_list.append((arn, cluster_name))
        print(f"{i}) {cluster_name}")
    
    print()
    selection = input("Select a cluster (number) or press 'q' to quit: ")
    
    if selection.lower() == 'q':
        return None
    
    try:
        index = int(selection) - 1
        if index < 0 or index >= len(clusters_list):
            print_error("Invalid selection.")
            return None
        
        return clusters_list[index]
    except ValueError:
        print_error("Invalid input. Please enter a number.")
        return None

def list_services_menu(ecs_client, cluster_arn, cluster_name):
    """Display a menu of services and prompt for selection."""
    service_arns = get_services(ecs_client, cluster_arn)
    
    if not service_arns:
        print_warning(f"No services found in cluster: {cluster_name}")
        return None
    
    print_header(f"SERVICES IN CLUSTER: {cluster_name}")
    
    services_list = []
    for i, arn in enumerate(service_arns, 1):
        service_name = arn.split('/')[-1]
        services_list.append((arn, service_name))
        print(f"{i}) {service_name}")
    
    print()
    selection = input("Select a service (number), press 'b' to go back, or 'q' to quit: ")
    
    if selection.lower() == 'q':
        return None
    
    if selection.lower() == 'b':
        return False
    
    try:
        index = int(selection) - 1
        if index < 0 or index >= len(services_list):
            print_error("Invalid selection.")
            return None
        
        return services_list[index]
    except ValueError:
        print_error("Invalid input. Please enter a number.")
        return None

def show_cluster_summary(ecs_client, cluster_arn, cluster_name):
    """Show a summary of a cluster."""
    print_header(f"CLUSTER SUMMARY: {cluster_name}")
    
    # Get cluster details
    clusters = get_cluster_details(ecs_client, [cluster_arn])
    if not clusters:
        print_error(f"Failed to get details for cluster: {cluster_name}")
        return
    
    cluster = clusters[0]
    print_cluster_summary(cluster)
    
    # Get services
    service_arns = get_services(ecs_client, cluster_arn)
    print(f"Services: {len(service_arns)}")
    
    # Get tasks
    task_arns = get_tasks(ecs_client, cluster_arn)
    print(f"Tasks: {len(task_arns)}")
    
    if task_arns:
        # Count tasks by status
        task_details = get_task_details(ecs_client, cluster_arn, task_arns)
        status_count = defaultdict(int)
        for task in task_details:
            status_count[task['lastStatus']] += 1
        
        for status, count in status_count.items():
            print(f"  {status}: {count}")
    
    print()
    input("Press Enter to continue...")

def show_service_summary(ecs_client, cluster_arn, cluster_name, service_arn, service_name):
    """Show a summary of a service."""
    print_header(f"SERVICE SUMMARY: {service_name}")
    
    # Get service details
    services = get_service_details(ecs_client, cluster_arn, [service_arn])
    if not services:
        print_error(f"Failed to get details for service: {service_name}")
        return
    
    service = services[0]
    print_service_summary(service)
    
    # Get tasks for this service
    task_arns = get_tasks(ecs_client, cluster_arn, service_arn)
    
    if task_arns:
        print(f"Tasks: {len(task_arns)}")
        
        # Get detailed task information
        task_details = get_task_details(ecs_client, cluster_arn, task_arns)
        
        # Group tasks by status
        tasks_by_status = defaultdict(list)
        for task in task_details:
            tasks_by_status[task['lastStatus']].append(task)
        
        # Print task summary by status
        for status, tasks in tasks_by_status.items():
            print(f"  {status}: {len(tasks)}")
        
        # Ask if user wants to see task details
        print()
        show_tasks = input("Show task details? (y/N): ")
        
        if show_tasks.lower() == 'y':
            print()
            print_header(f"TASKS IN SERVICE: {service_name}")
            for task in task_details:
                print_task_summary(task)
    else:
        print("No tasks found for this service.")
    
    print()
    input("Press Enter to continue...")

def show_task_list(ecs_client, cluster_arn, cluster_name, service_arn=None, service_name=None):
    """Show a list of tasks and allow selection for details."""
    if service_arn:
        print_header(f"TASKS IN SERVICE: {service_name}")
        task_arns = get_tasks(ecs_client, cluster_arn, service_arn)
    else:
        print_header(f"TASKS IN CLUSTER: {cluster_name}")
        task_arns = get_tasks(ecs_client, cluster_arn)
    
    if not task_arns:
        print_warning("No tasks found.")
        input("Press Enter to continue...")
        return
    
    # Get detailed task information
    task_details = get_task_details(ecs_client, cluster_arn, task_arns)
    
    # Display tasks with status
    tasks_list = []
    for i, task in enumerate(task_details, 1):
        task_id = task['taskArn'].split('/')[-1]
        status = task['lastStatus']
        
        # Add color to status
        if status == 'RUNNING':
            status_color = COLORS['GREEN']
        elif status == 'PENDING':
            status_color = COLORS['YELLOW']
        elif status == 'STOPPED':
            status_color = COLORS['RED']
        else:
            status_color = COLORS['NC']
        
        # Get task group or service name
        group = task.get('group', 'N/A')
        if group.startswith('service:'):
            group = group[8:]  # Remove 'service:' prefix
        
        tasks_list.append((task, task_id))
        print(f"{i}) {task_id} - Group: {group} - Status: {status_color}{status}{COLORS['NC']}")
    
    print()
    selection = input("Select a task for details (number), press 'b' to go back, or 'q' to quit: ")
    
    if selection.lower() == 'q':
        return None
    
    if selection.lower() == 'b':
        return False
    
    try:
        index = int(selection) - 1
        if index < 0 or index >= len(tasks_list):
            print_error("Invalid selection.")
            return False
        
        # Show details for the selected task
        task, task_id = tasks_list[index]
        print()
        print_header(f"TASK DETAILS: {task_id}")
        print_task_summary(task)
        
        input("Press Enter to continue...")
        return True
    except ValueError:
        print_error("Invalid input. Please enter a number.")
        return False

def main_menu(ecs_client):
    """Main menu for the application."""
    while True:
        print_header("MAIN MENU")
        print("1) View cluster summaries")
        print("2) View service details")
        print("3) View task details")
        print("4) View all resources (cluster -> services -> tasks)")
        print()
        
        selection = input("Select an option (1-4) or press 'q' to quit: ")
        
        if selection.lower() == 'q':
            return
        
        if selection == '1':
            # View cluster summaries
            cluster_info = list_clusters_menu(ecs_client)
            if cluster_info:
                cluster_arn, cluster_name = cluster_info
                show_cluster_summary(ecs_client, cluster_arn, cluster_name)
        
        elif selection == '2':
            # View service details
            cluster_info = list_clusters_menu(ecs_client)
            if not cluster_info:
                continue
            
            cluster_arn, cluster_name = cluster_info
            service_info = list_services_menu(ecs_client, cluster_arn, cluster_name)
            
            if service_info is False:  # 'b' was pressed
                continue
            
            if service_info:
                service_arn, service_name = service_info
                show_service_summary(ecs_client, cluster_arn, cluster_name, service_arn, service_name)
        
        elif selection == '3':
            # View task details
            cluster_info = list_clusters_menu(ecs_client)
            if not cluster_info:
                continue
            
            cluster_arn, cluster_name = cluster_info
            
            # Ask if user wants to filter by service
            print()
            filter_by_service = input("Filter tasks by service? (y/N): ")
            
            if filter_by_service.lower() == 'y':
                service_info = list_services_menu(ecs_client, cluster_arn, cluster_name)
                
                if service_info is False:  # 'b' was pressed
                    continue
                
                if service_info:
                    service_arn, service_name = service_info
                    show_task_list(ecs_client, cluster_arn, cluster_name, service_arn, service_name)
            else:
                show_task_list(ecs_client, cluster_arn, cluster_name)
        
        elif selection == '4':
            # View all resources
            cluster_info = list_clusters_menu(ecs_client)
            if not cluster_info:
                continue
            
            cluster_arn, cluster_name = cluster_info
            
            # First show cluster summary
            print()
            show_cluster_summary(ecs_client, cluster_arn, cluster_name)
            
            # Then list services
            service_arns = get_services(ecs_client, cluster_arn)
            if service_arns:
                service_details = get_service_details(ecs_client, cluster_arn, service_arns)
                
                for service in service_details:
                    service_name = service['serviceName']
                    service_arn = service['serviceArn']
                    print_service_summary(service)
                    
                    # Get tasks for this service
                    task_arns = get_tasks(ecs_client, cluster_arn, service_arn)
                    if task_arns:
                        task_details = get_task_details(ecs_client, cluster_arn, task_arns)
                        
                        # Print basic task information
                        print(f"Tasks in service {service_name}: {len(task_arns)}")
                        for task in task_details:
                            task_id = task['taskArn'].split('/')[-1]
                            status = task['lastStatus']
                            
                            # Add color to status
                            if status == 'RUNNING':
                                status_color = COLORS['GREEN']
                            elif status == 'PENDING':
                                status_color = COLORS['YELLOW']
                            elif status == 'STOPPED':
                                status_color = COLORS['RED']
                            else:
                                status_color = COLORS['NC']
                            
                            print(f"  {task_id}: {status_color}{status}{COLORS['NC']}")
                        
                        print()
            
            input("Press Enter to continue...")
        
        else:
            print_error("Invalid option. Please select a number from 1-4.")

def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description='ECS Status Utility')
    parser.add_argument('--profile', help='AWS profile to use')
    parser.add_argument('--region', help='AWS region to use')
    return parser.parse_args()

if __name__ == '__main__':
    args = parse_arguments()
    
    try:
        # Create boto3 session with optional profile and region
        session_kwargs = {}
        if args.profile:
            session_kwargs['profile_name'] = args.profile
        if args.region:
            session_kwargs['region_name'] = args.region
        
        session = boto3.Session(**session_kwargs)
        ecs_client = session.client('ecs')
        
        # Display welcome message
        print_header("AWS ECS STATUS UTILITY")
        print("This script helps you view detailed status information for ECS resources.")
        print_warning("Requirements:")
        print(" - AWS CLI configured with appropriate permissions")
        print(" - boto3 Python library (preinstalled in AWS CloudShell)")
        print()
        
        # Start the main menu
        main_menu(ecs_client)
        
        print("Exiting. Goodbye!")
    
    except KeyboardInterrupt:
        print("\nOperation cancelled by user. Exiting.")
        sys.exit(0)
    except Exception as e:
        print_error(f"An error occurred: {str(e)}")
        sys.exit(1)