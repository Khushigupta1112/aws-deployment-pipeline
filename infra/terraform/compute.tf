# Latest Amazon Linux 2023 AMI resolved via SSM Parameter Store (avoids
# hardcoding an AMI ID that goes stale).
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_key_pair" "deployer" {
  key_name   = "${var.project_name}-deployer-key"
  public_key = var.ssh_public_key

  tags = { Name = "${var.project_name}-deployer-key" }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name
  key_name               = aws_key_pair.deployer.key_name

  # Runs the user-data setup script (installs Docker, enables it on boot).
  user_data                   = file("${path.module}/../../scripts/ec2-user-data.sh")
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required" # enforce IMDSv2
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 12
    encrypted   = true
  }

  tags = { Name = "${var.project_name}-ec2" }
}
