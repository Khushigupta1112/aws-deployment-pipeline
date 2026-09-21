# AWS Setup — Manual (Console/CLI) Path

This is the primary, no-Terraform path. Every command here creates the exact
resources the Terraform files in `infra/terraform/` also describe.

Before starting:

- AWS CLI v2 installed and configured (`aws configure`) with an admin-level
  account on **your personal AWS account only** (never a shared/org account).
- `curl -s https://checkip.amazonaws.com` — note your public IP; you need it
  for the SSH rule.
- Run commands from the repository root.

Variables used throughout (set once per shell):

```bash
export AWS_REGION="ap-south-1"                 # pick your region
export MY_IP="$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')"
```

## 1. SSH key pair

```bash
ssh-keygen -t ed25519 -f ~/.ssh/aws-deployment-demo -C "aws-deployment-demo" -N ""
aws ec2 import-key-pair \
  --region "$AWS_REGION" \
  --key-name aws-deployment-demo-deployer-key \
  --public-key-material fileb://~/.ssh/aws-deployment-demo.pub
```

Keep the private file (`~/.ssh/aws-deployment-demo`) safe; you'll need it
locally for the GitHub secret later. Never commit it.

## 2. Networking: VPC, IGW, subnet, routing

```bash
VPC_ID=$(aws ec2 create-vpc \
  --region "$AWS_REGION" --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=aws-deployment-demo-vpc}]' \
  --query 'Vpc.VpcId' --output text)

IGW_ID=$(aws ec2 create-internet-gateway \
  --region "$AWS_REGION" \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=aws-deployment-demo-igw}]' \
  --query 'InternetGateway.InternetGatewayId' --output text)

aws ec2 attach-internet-gateway --region "$AWS_REGION" \
  --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"

SUBNET_ID=$(aws ec2 create-subnet \
  --region "$AWS_REGION" --vpc-id "$VPC_ID" \
  --cidr-block 10.0.1.0/24 \
  --availability-zone "${AWS_REGION}a" \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=aws-deployment-demo-public-subnet}]' \
  --query 'Subnet.SubnetId' --output text)

# A subnet is "public" because its route table sends 0.0.0.0/0 to the IGW
# AND it assigns public IPv4 addresses on launch.
aws ec2 create-route-table --region "$AWS_REGION" --vpc-id "$VPC_ID" \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=aws-deployment-demo-route-table}]'

RT_ID=$(aws ec2 describe-route-tables --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=aws-deployment-demo-route-table" \
  --query 'RouteTables[0].RouteTableId' --output text)

aws ec2 create-route --region "$AWS_REGION" --route-table-id "$RT_ID" \
  --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"

aws ec2 associate-route-table --region "$AWS_REGION" \
  --route-table-id "$RT_ID" --subnet-id "$SUBNET_ID"

aws ec2 modify-subnet-attribute --region "$AWS_REGION" \
  --subnet-id "$SUBNET_ID" --map-public-ip-on-launch
```

## 3. Security group

```bash
SG_ID=$(aws ec2 create-security-group \
  --region "$AWS_REGION" --group-name aws-deployment-demo-sg \
  --description "HTTP public, SSH restricted to admin IP" \
  --vpc-id "$VPC_ID" \
  --query 'GroupId' --output text)

aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$SG_ID" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

# SSH only from YOUR IP — never 0.0.0.0/0.
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$SG_ID" \
  --protocol tcp --port 22 --cidr "${MY_IP}/32"
```

## 4. IAM instance role (no static keys on the server)

```bash
aws iam create-role --role-name aws-deployment-demo-ec2-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "ec2.amazonaws.com"},
                   "Action": "sts:AssumeRole"}]
  }'

aws iam put-role-policy --role-name aws-deployment-demo-ec2-role \
  --policy-name aws-deployment-demo-ecr-pull --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {"Sid": "GetEcrAuthToken", "Effect": "Allow",
       "Action": ["ecr:GetAuthorizationToken"], "Resource": "*"},
      {"Sid": "PullAppImage", "Effect": "Allow",
       "Action": ["ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage",
                  "ecr:GetDownloadUrlForLayer"],
       "Resource": "arn:aws:ecr:'"$AWS_REGION"':'"$(aws sts get-caller-identity --query Account --output text)"':repository/aws-deployment-demo"}
    ]
  }'

aws iam create-instance-profile \
  --instance-profile-name aws-deployment-demo-instance-profile
aws iam add-role-to-instance-profile \
  --instance-profile-name aws-deployment-demo-instance-profile \
  --role-name aws-deployment-demo-ec2-role
```

## 5. ECR repository

```bash
aws ecr create-repository --region "$AWS_REGION" \
  --repository-name aws-deployment-demo \
  --image-scanning-configuration scanOnPush=true \
  --query 'repository.repositoryUri' --output text
```

## 6. S3 bucket for deployment logs

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
LOG_BUCKET="aws-deployment-demo-deploy-logs-${ACCOUNT_ID}"

aws s3api create-bucket --bucket "$LOG_BUCKET" --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"
# us-east-1 note: omit --create-bucket-configuration entirely.

aws s3api put-public-access-block --bucket "$LOG_BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-versioning --bucket "$LOG_BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket "$LOG_BUCKET" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

## 7. SNS topic + email subscription

```bash
SNS_ARN=$(aws sns create-topic --name aws-deployment-alerts \
  --query 'TopicArn' --output text)

aws sns subscribe --topic-arn "$SNS_ARN" \
  --protocol email --notification-endpoint you@example.com
```

Check your inbox and **click the confirmation link** — until you do, SNS will
not deliver anything (there is an explicit "confirmed" check below).

## 8. CloudWatch alarms

```bash
INSTANCE_ID="<set after step 10>"

aws cloudwatch put-metric-alarm \
  --alarm-name aws-deployment-demo-cpu-high \
  --namespace AWS/EC2 --metric-name CPUUtilization \
  --statistic Average --period 300 --evaluation-periods 2 \
  --threshold 70 --comparison-operator GreaterThanThreshold \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --treat-missing-data notBreaching \
  --alarm-actions "$SNS_ARN" --ok-actions "$SNS_ARN"

aws cloudwatch put-metric-alarm \
  --alarm-name aws-deployment-demo-instance-status-check \
  --namespace AWS/EC2 --metric-name StatusCheckFailed \
  --statistic Maximum --period 60 --evaluation-periods 2 \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold \
  --dimensions Name=InstanceId,Value="$INSTANCE_ID" \
  --treat-missing-data notBreaching \
  --alarm-actions "$SNS_ARN" --ok-actions "$SNS_ARN"
```

## 9. GitHub OIDC role (deploy credentials)

```bash
OIDC_ARN=$(aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --query 'OpenIDConnectProviderArn' --output text)

# GITHUB_REPO must match "<owner>/<repo>" where you push this project.
export GITHUB_REPO="Khushigupta1112/aws-deployment-pipeline"

aws iam create-role --role-name aws-deployment-demo-github-deploy-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow",
      "Principal": {"Federated": "'"${OIDC_ARN}"'"},
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {"token.actions.githubusercontent.com:aud": "sts.amazonaws.com"},
        "StringLike": {"token.actions.githubusercontent.com:sub":
          "repo:'"${GITHUB_REPO}"':ref:refs/heads/main"}
      }}]
  }'

aws iam put-role-policy --role-name aws-deployment-demo-github-deploy-role \
  --policy-name aws-deployment-demo-deploy-permissions \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {"Effect": "Allow", "Action": ["ecr:GetAuthorizationToken"], "Resource": "*"},
      {"Effect": "Allow", "Action": ["ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
        "ecr:CompleteLayerUpload", "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart", "ecr:PutImage"],
       "Resource": "arn:aws:ecr:'"$AWS_REGION"':'"$(aws sts get-caller-identity --query Account --output text)"':repository/aws-deployment-demo"},
      {"Effect": "Allow", "Action": ["s3:PutObject"],
       "Resource": "arn:aws:s3:::'"$LOG_BUCKET"'/deployments/*"}
    ]
  }'
```

The role ARN printed by the create-role call is your `AWS_ROLE_ARN` secret.

## 10. EC2 instance

```bash
AMI_ID=$(aws ssm get-parameter \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' --output text)

aws ec2 run-instances --region "$AWS_REGION" \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --subnet-id "$SUBNET_ID" \
  --security-group-ids "$SG_ID" \
  --iam-instance-profile Name=aws-deployment-demo-instance-profile \
  --key-name aws-deployment-demo-deployer-key \
  --user-data fileb://scripts/ec2-user-data.sh \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=12,VolumeType=gp3,Encrypted=true}' \
  --metadata-options 'HttpTokens=required' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=aws-deployment-demo-ec2}]'
```

## 11. Verify the host

```bash
INSTANCE_ID=$(aws ec2 describe-instances --region "$AWS_REGION" \
  --filters "Name=tag:Name,Values=aws-deployment-demo-ec2" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text)

# Wait until both status checks pass before continuing.
aws ec2 wait instance-status-ok --region "$AWS_REGION" --instance-ids "$INSTANCE_ID"

EC2_HOST=$(aws ec2 describe-instances --region "$AWS_REGION" \
  --filters "Name=tag:Name,Values=aws-deployment-demo-ec2" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

ssh -i ~/.ssh/aws-deployment-demo ec2-user@"$EC2_HOST" 'docker info | grep -E "Server Version" && aws --version'
```

## 12. SNS subscription confirmation check

```bash
aws sns list-subscriptions-by-topic --topic-arn "$SNS_ARN" \
  --query 'Subscriptions[].[Endpoint,Protocol,SubscriptionArn]'
```

`SubscriptionArn` shows `PendingConfirmation` until you click the link.
Only record the SNS email as working after you see the numeric subscription
ARN here.

After this, set the GitHub secrets listed in the README, push to `main`, and
the pipeline takes over.
