# ecs-exec.sh

`ecs-exec.sh` is a terminal UI for quickly attaching to containers on ECS which have "ECS Exec" enabled. Learn more here: [ECS Exec Documentation](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-exec.html).

## Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- `jq` installed (for JSON parsing)
- ECS Exec enabled on your cluster and task definition

### Installation

1. Clone the repository or download the `ecs-exec.sh` script.
2. Ensure the script has execute permissions:
   ```bash
   chmod +x ecs-exec.sh
   ```

### Usage

Run the script:

```bash
./ecs-exec.sh
```

Follow the on-screen prompts to select a cluster, task, and container to connect to.

## Features

- List available ECS clusters
- List tasks within a selected cluster
- List containers within a selected task
- Connect to a container using ECS Exec

## License

This project is licensed under the MIT License.
