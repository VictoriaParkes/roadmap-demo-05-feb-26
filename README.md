# roadmap-demo-05-feb-26

## Application Overview
A **containerized blog platform** built with Flask (Python), deployed on AWS in the `eu-west-2` region. Users can create blog posts with images and view them. The app uses DynamoDB for data persistence and Cloudinary for image hosting.

## Infrastructure

| Component | Details |
|    ---    | ------- |
| VPC       | `demo-vpc` - CIDR `10.0.0.0/16`, spanning 3 AZs (eu-west-2a/b/c) |
| Compute   | EC2 `t3.micro` instances running Amazon Linux 2023 with Docker |
| Container Registry | ECR repo `roadmap-demo-app` - scan on push, keeps last 10 images |
| Database | DynamoDB table `BlogData` - PAY_PER_REQUEST, partition key `PostI`d` (Number) |
| Secrets	| AWS Secrets Manager stores Cloudinary credentials |
| Load Balancer	| Internet-facing ALB on port 80, health checks on `/health` |
| Monitoring | CloudWatch alarms on average CPU utilization |

## Networking

- **Public subnets** (`10.0.4.0/24`, `10.0.5.0/24`, `10.0.6.0/24`) - host the ALB and NAT Gateway

- **Private subnets** (`10.0.1.0/24`, `10.0.2.0/24`, `10.0.3.0/24`) — host EC2 instances (no direct internet access)

- **NAT Gateway** — allows private instances to reach the internet (pull ECR images, access Cloudinary/DynamoDB)

- **Security groups**:

    - ALB SG: ingress TCP 80 from a prefix list, egress all

    - Instance SG: ingress TCP 80 from ALB SG only, egress all

- This means EC2 instances are **never directly accessible** from the internet — all traffic must pass through the ALB

## Data Flow

1. **Viewing posts (GET /)**: User → ALB → EC2 → DynamoDB `table.scan()` → sorted posts rendered as HTML → returned to user

2. Creating posts (POST /create):

    - User submits form with title, content, optional image

    - ALB forwards to an EC2 instance

    - Image uploaded to Cloudinary → returns secure URL

    - Post stored in DynamoDB (`PostId`, `title`, `content`, `image` URL, `date`)

    - User redirected to homepage

3. **Health checks**: ALB sends `GET /health` every 30s → Flask checks DynamoDB table status → returns 200 or 500

## Autoscaling

- **Auto Scaling Group**: min 3, max 6, desired 3 instances spread across 3 AZs

- **Scale up**: CloudWatch alarm triggers when average CPU > 50% for 1 × 60s period → adds 1 instance, 60s cooldown

- **Scale down**: CloudWatch alarm triggers when average CPU < 20% for 1 × 60s period → removes 1 instance, 60s cooldown

- **Health check type**: ELB — if the ALB marks an instance unhealthy (2 consecutive failed checks), the ASG terminates and replaces it

- **Demo CPU cycling script**: baked into user data to simulate load — 3 minutes high CPU / 3 minutes low CPU, synchronized across instances to demonstrate scaling in action


## Deployment Flow

1. Docker image built locally (`docker buildx build --platform linux/amd64`)

2. Pushed to ECR

3. On instance boot (user data script): install Docker → authenticate to ECR → pull latest image → fetch Cloudinary secrets from Secrets Manager → run container mapping port 80→8080

4. IAM role (`ec2-ecr-access-role`) grants instances permission to pull from ECR and read from Secrets Manager

## Best Practice Setup:
### use new terminal each refresh

1. Create access keys (you need some initial credential)

    IAM → Users → Security credentials → Create access key

2. Create role:\
    Trusted entity type = AWS account\
    An AWS account = This account\
    Add permission policies\
        - admin\
    Name = terraform-execution

3. Configure with short-lived credentials:

    `aws configure`\
    `# Enter your keys`

4. Use STS 

    1. to get temporary credentials (15 min - 12 hours):

    `aws sts get-session-token --duration-seconds 3600`

    2. Export the temporary credentials:

    `export AWS_ACCESS_KEY_ID=<from output>`\
    `export AWS_SECRET_ACCESS_KEY=<from output>`\
    `export AWS_SESSION_TOKEN=<from output>`\

    ### OR
    1. Use STS to get temporary credentials (15 min - 12 hours) and copy the output values and export them:

    `eval $(aws sts get-session-token --duration-seconds 3600 --output json | jq -r '.Credentials | "export AWS_ACCESS_KEY_ID=\(.AccessKeyId)\nexport AWS_SECRET_ACCESS_KEY=\(.SecretAccessKey)\nexport AWS_SESSION_TOKEN=\(.SessionToken)"')`


    ### *Can also edit `.config` file manually*

        .config:

        [default]\
        region = eu-west-2\
        output = json\
        role_arn = arn:aws:iam::<aws_account_id>:role/<role_name>\
        source_profile = user1

        .credentials:

        [user1]\
        aws_access_key_id = <Access_key_ID>>\
        aws_secret_access_key = <Secret_access_key>



5. Check caller identity to verify user is used:

    `aws sts get-caller-identity`

    output:

    `"UserId": "<Access_key_ID>>:botocore-session-1770646657",`\
    `"Account": "<aws_account_id>",`\
    `"Arn": "arn:aws:sts::<aws_account_id>:assumed-role/<role_name>/botocore-session-1770646657"`

6. Store long-lived keys securely:

    `chmod 600 ~/.aws/credentials`

---
## Commands:
### Docker

- `docker buildx build --platform linux/amd64 -t roadmap-demo-app:latest .`

### Terraform
- Check for running Terraform processes: `ps aux | grep terraform`

---
To find your ~/.aws/config file, look in your user's home directory. The exact path depends on your operating system: 
1. Standard File Paths
Linux, macOS, or Unix: /Users/USERNAME/.aws/config (often abbreviated as ~/.aws/config).
Windows: C:\Users\USERNAME\.aws\config (accessible via the %USERPROFILE%\.aws\config environment variable). 

2. Quick Terminal Commands 
If you want to view or verify the file location quickly, use these commands:
View file contents:
Mac/Linux: cat ~/.aws/config.
Windows (Command Prompt): type %USERPROFILE%\.aws\config.
Identify active config: Run aws configure list to see exactly which file the AWS CLI is currently using for your settings. 

3. Hidden Folder Tips
Dotfiles: The .aws folder is a "hidden" directory because it starts with a period.
On macOS: In Finder, press Cmd + Shift + . to reveal hidden files.
On Windows: Ensure "Hidden items" is checked in the View tab of File Explorer. 

4. Custom Locations
If the file isn't in the default spot, check if the AWS_CONFIG_FILE environment variable has been set to a different path. 

Note: If the file does not exist yet, you can create it automatically by running the aws configure command in your terminal. 
