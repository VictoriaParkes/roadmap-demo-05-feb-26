# Infrastructure Diagrams — roadmap-demo-05-feb-26

## 1. High-Level Architecture

```mermaid
graph TB
    subgraph Internet
        User[👤 User]
    end

    subgraph AWS["AWS (eu-west-2)"]
        subgraph VPC["VPC - demo-vpc (10.0.0.0/16)"]
            subgraph Public["Public Subnets"]
                ALB[Application Load Balancer<br/>Port 80 HTTP]
            end

            subgraph Private["Private Subnets (3 AZs)"]
                subgraph ASG["Auto Scaling Group (min:3, max:6)"]
                    EC2a[EC2 t3.micro<br/>eu-west-2a]
                    EC2b[EC2 t3.micro<br/>eu-west-2b]
                    EC2c[EC2 t3.micro<br/>eu-west-2c]
                end
            end

            NAT[NAT Gateway]
        end

        ECR[ECR Repository<br/>roadmap-demo-app]
        DDB[DynamoDB<br/>BlogData Table]
        SM[Secrets Manager<br/>cloudinary-credentials]
        CW[CloudWatch Alarms<br/>CPU Monitoring]
    end

    subgraph External
        Cloudinary[☁️ Cloudinary<br/>Image Hosting]
    end

    User -->|HTTP :80| ALB
    ALB -->|HTTP :80| EC2a
    ALB -->|HTTP :80| EC2b
    ALB -->|HTTP :80| EC2c
    EC2a --> DDB
    EC2b --> DDB
    EC2c --> DDB
    EC2a --> Cloudinary
    EC2b --> Cloudinary
    EC2c --> Cloudinary
    EC2a -.->|Pull Image| ECR
    EC2b -.->|Pull Image| ECR
    EC2c -.->|Pull Image| ECR
    EC2a -.->|Get Secret| SM
    EC2b -.->|Get Secret| SM
    EC2c -.->|Get Secret| SM
    Private -->|Outbound| NAT
    NAT -->|Internet| Internet
    CW -->|Scale Up/Down| ASG
```

## 2. Network Architecture

```mermaid
graph TB
    subgraph VPC["VPC: demo-vpc (10.0.0.0/16)"]
        subgraph AZ_A["Availability Zone: eu-west-2a"]
            PubA["Public Subnet<br/>10.0.4.0/24"]
            PrivA["Private Subnet<br/>10.0.1.0/24"]
        end

        subgraph AZ_B["Availability Zone: eu-west-2b"]
            PubB["Public Subnet<br/>10.0.5.0/24"]
            PrivB["Private Subnet<br/>10.0.2.0/24"]
        end

        subgraph AZ_C["Availability Zone: eu-west-2c"]
            PubC["Public Subnet<br/>10.0.6.0/24"]
            PrivC["Private Subnet<br/>10.0.3.0/24"]
        end

        IGW[Internet Gateway]
        NAT[NAT Gateway]
    end

    Internet((Internet))

    Internet <--> IGW
    IGW <--> PubA
    IGW <--> PubB
    IGW <--> PubC
    PubA --> NAT
    NAT --> PrivA
    NAT --> PrivB
    NAT --> PrivC
```

## 3. Security Groups & Traffic Flow

```mermaid
graph LR
    subgraph Internet
        User[👤 User<br/>Prefix List]
    end

    subgraph ALB_SG["SG: load-balancer-security-group"]
        ALB[ALB<br/>Ingress: TCP 80 from Prefix List<br/>Egress: All traffic]
    end

    subgraph Instance_SG["SG: instance-security-group"]
        EC2[EC2 Instances<br/>Ingress: TCP 80 from ALB SG<br/>Egress: All traffic]
    end

    User -->|TCP 80| ALB
    ALB -->|TCP 80| EC2
    EC2 -->|All outbound| Internet
```

## 4. Auto Scaling & Monitoring

```mermaid
graph TD
    subgraph CloudWatch["CloudWatch Monitoring"]
        HighCPU["⚠️ High CPU Alarm<br/>Threshold: >50%<br/>Period: 60s<br/>Eval Periods: 1"]
        LowCPU["✅ Low CPU Alarm<br/>Threshold: <20%<br/>Period: 60s<br/>Eval Periods: 1"]
    end

    subgraph Scaling["Auto Scaling Policies"]
        ScaleUp["Scale Up Policy<br/>+1 instance<br/>Cooldown: 60s"]
        ScaleDown["Scale Down Policy<br/>-1 instance<br/>Cooldown: 60s"]
    end

    subgraph ASG["Auto Scaling Group"]
        Min["Min: 3"]
        Desired["Desired: 3"]
        Max["Max: 6"]
    end

    HighCPU -->|Triggers| ScaleUp
    LowCPU -->|Triggers| ScaleDown
    ScaleUp -->|Increase capacity| ASG
    ScaleDown -->|Decrease capacity| ASG
```

## 5. Application Deployment Flow

```mermaid
graph TD
    subgraph Build["Build Phase"]
        Code[Application Code<br/>Flask + Python 3.9]
        Docker[Dockerfile]
        Code --> Docker
        Docker -->|docker build| Image[Container Image]
    end

    subgraph Registry["AWS ECR"]
        ECR[roadmap-demo-app<br/>Lifecycle: Keep last 10 images<br/>Scan on push: enabled]
    end

    subgraph Deploy["EC2 Instance Boot (User Data)"]
        Step1[1. Install Docker]
        Step2[2. ECR Login]
        Step3[3. Pull Image]
        Step4[4. Get Secrets from SM]
        Step5[5. Run Container<br/>-p 80:8080]
    end

    Image -->|docker push| ECR
    ECR -->|docker pull| Step3
    Step1 --> Step2 --> Step3 --> Step4 --> Step5
```

## 6. IAM & Permissions

```mermaid
graph TD
    subgraph IAM["IAM Configuration"]
        Role["IAM Role: ec2-ecr-access-role<br/>Trust: ec2.amazonaws.com"]
        Profile["Instance Profile: ec2-instance-profile"]
        ECRPolicy["AWS Managed Policy<br/>AmazonEC2ContainerRegistryPullOnly"]
        SMPolicy["Inline Policy<br/>secretsmanager:GetSecretValue<br/>Resource: cloudinary-credentials"]
    end

    subgraph Services["AWS Services Accessed"]
        ECR[ECR - Pull Images]
        SM[Secrets Manager - Read Secrets]
    end

    Role --> Profile
    ECRPolicy --> Role
    SMPolicy --> Role
    Profile --> EC2[EC2 Instances]
    EC2 -->|Pull| ECR
    EC2 -->|GetSecretValue| SM
```

## 7. Application Data Flow

```mermaid
sequenceDiagram
    participant U as User Browser
    participant ALB as Load Balancer
    participant EC2 as EC2 (Flask App)
    participant DDB as DynamoDB
    participant CLD as Cloudinary

    Note over U,CLD: View Posts (GET /)
    U->>ALB: GET /
    ALB->>EC2: Forward request
    EC2->>DDB: table.scan()
    DDB-->>EC2: All posts
    EC2-->>ALB: Rendered HTML
    ALB-->>U: Blog page

    Note over U,CLD: Create Post (POST /create)
    U->>ALB: POST /create (title, content, image)
    ALB->>EC2: Forward request
    EC2->>CLD: Upload image
    CLD-->>EC2: Image URL
    EC2->>DDB: table.put_item(PostId, title, content, image_url, date)
    DDB-->>EC2: Success
    EC2-->>ALB: Redirect to /
    ALB-->>U: 302 Redirect

    Note over U,CLD: Health Check
    ALB->>EC2: GET /health
    EC2->>DDB: Check table_status
    DDB-->>EC2: OK
    EC2-->>ALB: 200 {"status": "healthy"}
```

## Summary Table

| Component | Resource | Details |
|-----------|----------|---------|
| **Network** | VPC | 10.0.0.0/16, 3 AZs, NAT Gateway |
| **Compute** | EC2 (ASG) | t3.micro, Amazon Linux 2023, min 3 / max 6 |
| **Load Balancer** | ALB | Public-facing, HTTP:80, health check on /health |
| **Container Registry** | ECR | roadmap-demo-app, scan on push, keep last 10 |
| **Database** | DynamoDB | BlogData table, PAY_PER_REQUEST, hash key: PostId |
| **Secrets** | Secrets Manager | Cloudinary credentials (cloud_name, api_key, api_secret) |
| **Monitoring** | CloudWatch | CPU alarms at >50% (scale up) and <20% (scale down) |
| **IAM** | Role + Profile | ECR pull + Secrets Manager read |
| **External** | Cloudinary | Image upload and hosting |