# COST.md — Cost Control for the Demo

This stack was designed for a student budget. Figures are order-of-magnitude
estimates (2026, typical on-demand rates) — verify in the AWS Pricing
Calculator before judging anything.

## What runs and what it costs (approximate, monthly if left on 24/7)

| Resource | Spec | Rough monthly cost | Notes |
| --- | --- | --- | --- |
| EC2 t3.micro | 1 vCPU, 1 GB | ~$3–4 (region-dependent) | Free Tier eligible (750 h/mo) if your account is still eligible |
| EBS root (gp3, 12 GB) | | ~$1 | 12 GB × $0.08/GB-mo |
| Public IPv4 | 1 address | ~$3.6 | ~$0.005/h since Feb 2024; Free Tier includes 750 h/mo |
| ECR | 1 image ≈ 200–300 MB, grows per commit | < $0.05 | $0.10/GB-mo; old images accumulate — prune occasionally |
| S3 deployment logs | KB-sized text files | ≈ $0 | Negligible; 90-day lifecycle expiry |
| CloudWatch | 2 alarms, basic metrics | < $0.30 | Alarms ~$0.10 each; basic EC2 metrics are free |
| SNS | email notifications | ≈ $0 | Email delivery is effectively free at this volume |
| NAT Gateway | **NOT DEPLOYED** | **$0** | Would be ~$32+/mo + data — avoided on purpose |

**Total if left running: roughly $8–10/month** (less under Free Tier), and
the biggest levers are EC2 compute hours + public IPv4.

## Deliberate omissions

- **No NAT Gateway** — a single public subnet means EC2 reaches the internet
  (ECR pulls) directly via the Internet Gateway. A NAT Gateway would only
  make sense with a private subnet, which this demo intentionally doesn't
  have.
- **No ALB** (~$16+/mo), no Route 53 hosted zone, no extra EBS volumes.

## Demonstration strategy (pay as little as possible)

- Deploy, demo, and **stop the instance** between sessions:
  `aws ec2 stop-instances --instance-ids <id>` — stopping halts compute
  charges (you still pay ~$1/mo for the EBS volume, and stopped instances
  keep their public IP *only* if you switched to an Elastic IP; a default
  auto-assigned IP is released on stop, so `EC2_HOST` may change on restart).
- **Terminate** everything when the demo is done for good (Cleanup section).

## Full cleanup procedure

```bash
cd infra/terraform
terraform destroy     # removes VPC, IGW, subnet, SG, IAM, ECR, S3, SNS, alarms, EC2
```

Manual path equivalent (if you followed `docs/aws-setup.md`):

```bash
# 1. EC2
aws ec2 terminate-instances --instance-ids <id>

# 2. S3 bucket (objects first — lifecycle already expires logs but clean now)
aws s3 rm "s3://<log-bucket>" --recursive
aws s3api delete-bucket --bucket <log-bucket>

# 3. ECR images + repo
aws ecr batch-delete-image --repository-name aws-deployment-demo \
  --image-ids imageTag=<sha> imageTag=latest
aws ecr delete-repository --repository-name aws-deployment-demo --force

# 4. CloudWatch alarms
aws cloudwatch delete-alarms --alarm-names \
  aws-deployment-demo-cpu-high aws-deployment-demo-instance-status-check

# 5. SNS
aws sns delete-topic --topic-arn <sns-arn>

# 6. IAM (roles, policies, instance profile, OIDC provider, key pair)
aws iam detach-... / delete-... (list each: roles, inline policies,
  instance profile, OIDC provider)
aws ec2 delete-key-pair --key-name aws-deployment-demo-deployer-key

# 7. Security group, subnet, route table, IGW, VPC (order: SG → RT assoc → RT → IGW detach → VPC)
```

## Cost-awareness talking points (interview gold)

- "I sized the instance to the workload and Free Tier, not to what looked
  impressive."
- "I avoided a NAT Gateway — with one public subnet it would buy nothing
  and cost $32+/month."
- "Logs are tiny and expire in 90 days, so storage cost is effectively zero."
- "I know exactly how to tear the stack down in one command — that matters
  as much as standing it up."
