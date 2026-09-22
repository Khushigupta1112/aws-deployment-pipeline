# Account and partition context used for bucket naming and ARN scoping.
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
