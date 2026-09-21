output "ecr_repository_url" {
  description = "ECR repository URL (used as ECR_REPOSITORY in GitHub secrets)"
  value       = aws_ecr_repository.app.repository_url
}

output "github_deploy_role_arn" {
  description = "IAM role ARN for GitHub Actions OIDC (put this in the AWS_ROLE_ARN secret)"
  value       = aws_iam_role.github_deploy.arn
}

output "ec2_public_ip" {
  description = "Public IP of the deployment host (put this in the EC2_HOST secret)"
  value       = aws_instance.app.public_ip
}

output "ec2_ssh_command" {
  description = "Ready-to-use SSH command for the deployment host"
  value       = "ssh -i /path/to/private/key ec2-user@${aws_instance.app.public_ip}"
}

output "deploy_log_bucket" {
  description = "S3 bucket receiving deployment logs (put this in the S3_BUCKET secret)"
  value       = aws_s3_bucket.logs.bucket
}

output "sns_topic_arn" {
  description = "SNS topic receiving CloudWatch alarm notifications"
  value       = aws_sns_topic.alerts.arn
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "security_group_id" {
  value = aws_security_group.app.id
}
