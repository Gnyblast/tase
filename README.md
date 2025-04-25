<p align="center">
<img src="./trans_bg_wo_wm.png" alt="drawing" width="200"/>
<p>

> [!IMPORTANT]  
> Tase is not working at the moment, being actively developed.

# Tase

## Log Management Application

Tase is a lightweight log management system written in Zig. It consists of a daemon running on a master server and lightweight agents deployed across multiple servers. With a single config.yaml, Tase allows centralized control over log file management, including deletion, rotation, and truncation.

## Features

1. **Master-Agent Architecture**: The master server manages configurations and schedules, while agents execute log management tasks.
2. **YAML-Based Configuration**: The master server reads a `config.yaml` file to determine agent behavior and scheduling.
3. **Cron-based Scheduling**: The application uses cron-based scheduling to execute the log management tasks at predefined intervals.
4. **Truncate Logs**: The application can truncate log files that are older than a specified number of days or exceed a certain size.
5. **Rotate Logs**: The application can rotate log files, optionally compressing the archived files using the GZip algorithm. It can also delete archived logs older than a specified number of days.
6. **Delete Logs**: The application can delete log files that are older than a specified number of days or exceed a certain size.

## Installation

Tase is written in Zig, and to build and install it, follow these steps:

```sh
# Clone the repository
git clone https://github.com/Gnyblast/tase.git
cd tase

# Build the application
zig build

# Run the master daemon
zig-out/bin/tase -m master -c /path/to/config.yml

# Run the agent daemon on other servers that can communicate with master server
zig-out/bin/tase --agent --secret <a-generated-secret-that-matches-to-config> --port 7423 --master-host localhost --master-port 7423
```

## Configuration Reference

### Configuration File Structure

The application uses a YAML configuration file with the following main sections:

#### 1. Configs (`configs`)

Each config defines a log management task with the following properties:

| Property           | Type     | Description                                                                           | Default | Required |
| ------------------ | -------- | ------------------------------------------------------------------------------------- | ------- | -------- |
| `app_name`         | string   | Name of the application                                                               | -       | Yes      |
| `logs_dir`         | string   | Directory containing log files                                                        | -       | Yes      |
| `log_files_regexp` | string   | Regular expression to match log files                                                 | -       | Yes      |
| `cron_expression`  | string   | Cron schedule for the log management task                                             | -       | Yes      |
| `run_agent_names`  | string[] | List of agents to run this task ("local" is a reserved word for master server itself) | -       | Yes      |
| `action`           | object   | Log management strategy details                                                       | -       | Yes      |

#### 2. Action Strategies

The `action` object supports three strategies:

##### Truncate Strategy

| Property       | Type   | Description                               | Default | Constraints |
| -------------- | ------ | ----------------------------------------- | ------- | ----------- |
| `strategy`     | string | Must be `"truncate"`                      | -       | Required    |
| `from`         | string | Where to truncate (`"top"` or `"bottom"`) | -       | Required    |
| `if.condition` | string | Condition type (`"days"` or `"size"`)     | -       | Required    |
| `if.operator`  | string | Comparison operator (`">"`, `"<"`, `"="`) | -       | Required    |
| `if.operand`   | number | Threshold value                           | -       | Required    |

##### Rotate Strategy

| Property                          | Type    | Description                           | Default  | Optional                    |
| --------------------------------- | ------- | ------------------------------------- | -------- | --------------------------- |
| `strategy`                        | string  | Must be `"rotate"`                    | -        | Required                    |
| `if.condition`                    | string  | Condition type (`"days"` or `"size"`) | -        | Required                    |
| `if.operator`                     | string  | Comparison operator                   | -        | Required                    |
| `if.operand`                      | number  | Threshold value                       | -        | Required                    |
| `delete_archives_older_than_days` | number  | Days to keep archives                 | 7        | Yes                         |
| `compress`                        | boolean | Enable compression                    | `false`  | Yes                         |
| `compression_type`                | string  | Compression algorithm (`"gzip"`)      | `"gzip"` | Optional if `compress=true` |
| `compression_level`               | number  | Compression level (4-9)               | 4        | Optional if `compress=true` |

##### Delete Strategy

| Property       | Type   | Description                           | Default | Constraints |
| -------------- | ------ | ------------------------------------- | ------- | ----------- |
| `strategy`     | string | Must be `"delete"`                    | -       | Required    |
| `if.condition` | string | Condition type (`"days"` or `"size"`) | -       | Required    |
| `if.operator`  | string | Comparison operator                   | -       | Required    |
| `if.operand`   | number | Threshold value                       | -       | Required    |

#### 3. Agents Configuration

| Property   | Type   | Description                                     | Default |
| ---------- | ------ | ----------------------------------------------- | ------- |
| `name`     | string | Agent name ("local" is reserved cannot be used) | -       |
| `hostname` | string | Agent hostname                                  | -       |
| `port`     | number | Agent port                                      | -       |
| `secret`   | string | Authentication secret                           | -       |

#### 4. Server Configuration

| Property    | Type   | Description      | Default       |
| ----------- | ------ | ---------------- | ------------- |
| `host`      | string | Server hostname  | `"127.0.0.1"` |
| `port`      | number | Server port      | `7423`        |
| `type`      | string | Server type      | `"tcp"`       |
| `time_zone` | string | Server time zone | `"UTC"`       |

## Example Configuration

```yaml
configs:
  - app_name: "rotate_logs"
    logs_dir: "/var/log/myapp"
    log_files_regexp: ".*\\.log"
    cron_expression: "0 0 * * *"
    run_agent_names: ["agent_1"]
    action:
      strategy: rotate
      if:
        condition: days
        operator: ">"
        operand: 7
      compress: true
      compression_type: gzip
      compression_level: 5

agents:
  - name: agent_1
    hostname: "192.xxx.xxx.xxx"
    port: 7423
    secret: "your-secret-key"

server:
  host: "127.0.0.1"
  port: 7423
  time_zone: "UTC"
```

## License

This project is licensed under the [MIT License](LICENSE).

## Contributing

Contributions are welcome! Feel free to submit issues and pull requests on [GitHub](https://github.com/Gnyblast/tase).

## Author

Developed by [Gnyblast](https://github.com/Gnyblast).
