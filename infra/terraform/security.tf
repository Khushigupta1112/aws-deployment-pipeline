resource "aws_security_group" "app" {
  name        = "${var.project_name}-sg"
  description = "HTTP from anywhere; SSH restricted to the administrator IP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from anywhere (the application entry point)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH restricted to administrator IP (never 0.0.0.0/0)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  egress {
    description = "All outbound traffic (ECR login, image pull)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg" }
}
