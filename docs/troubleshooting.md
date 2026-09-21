# Troubleshooting

Real error messages, real causes, real fixes.

## Workflow fails at "Run tests"

- Read the failing assertion in the log — Vitest prints expected/received.
- Reproduce locally first: `cd app && npm ci && npm test`.
- A red test job means deploy never starts (`needs: test`). This is correct
  behavior, not a bug.

## Workflow fails at "Configure AWS credentials"

- `No credentials / not authorized` → `AWS_ROLE_ARN` secret missing or wrong.
  The ARN must be the `github-deploy-role` from Terraform output
  `github_deploy_role_arn`.
- `Not authorized to perform sts:AssumeRoleWithWebIdentity` → the trust
  policy's `sub` condition doesn't match. It must be
  `repo:<owner>/<repo>:ref:refs/heads/main` and the run must actually be a
  push to `main` (manual dispatch from a branch also sends that branch's ref —
  run it from `main`).

## Workflow fails at ECR login or push

- Login error mentioning 401: check `AWS_REGION` secret matches the region
  where Terraform created the repository.
- Repository not found: `ECR_REPOSITORY` secret must be exactly the repo name
  (`aws-deployment-demo`), not the full URI.
- If someone set the repository to IMMUTABLE manually, the second push of
  `latest` fails — keep MUTABLE.

## Workflow fails at SSH ("Connection timed out")

- The security group allows port 22 only from `ssh_allowed_cidr`. If your IP
  changed since apply, re-apply Terraform or edit the SG rule. Check your
  current IP: `curl -s https://checkip.amazonaws.com`.
- Instance stopped or terminated → check the console; `terraform apply` after
  `terraform start`… no — use `aws ec2 start-instances` if you stopped it for
  cost saving, then re-run the deploy manually via `workflow_dispatch`.
- Key mismatch → `Permission denied (publickey)`: the `EC2_SSH_PRIVATE_KEY`
  secret must be the **private** key (complete, with header/footer, trailing
  newline preserved when pasting into the secret box).

## Deploy step fails with "health check FAILED"

1. SSH into the host: `ssh -i ~/.ssh/aws-deployment-demo ec2-user@<ip>`.
2. `docker ps -a` — is the container up? `docker logs aws-deployment-demo`.
3. Common causes:
   - ECR pull denied → instance profile missing (check
     `aws sts get-caller-identity` on the host; the instance role must be
     attached).
   - Wrong tag deployed → the workflow passes `github.sha`; confirm the run
     matches your commit.
4. Note: if the NEW image failed health checks and rollback succeeded, the
   workflow still fails (exit 1) while the OLD version keeps serving —
   that's the documented rollback behavior. The step log shows
   `Rollback SUCCESS` and the S3 log shows `deployment_status=FAILED`.

## S3 log upload fails

- `Access Denied` → the OIDC role policy allows `s3:PutObject` only on
  `deployments/*` under the bucket in the `S3_BUCKET` secret. Bucket name
  mismatch (typo, wrong account) is the usual cause.

## Alarm never fires after CPU test

- Standard-instance metrics arrive every **5 minutes**. After starting the
  load generator, the alarm needs 2 consecutive 5-minute datapoints above
  threshold: expect **~10–15 minutes** before it flips to ALARM.
- Check the metric in the CloudWatch console (EC2 → instance → Monitoring)
  before blaming the alarm.
- Alarm notification: SNS emails require the **confirmed** subscription.

## No SNS email arrives

- Subscription still `PendingConfirmation` (check
  `aws sns list-subscriptions-by-topic`). Click the link in the confirmation
  email SNS sent when the subscription was created.
- Check spam/junk folders for both the confirmation request and alerts.
- `ok_actions` also notify on recovery — you should get an email when the
  alarm returns to OK.

## Terraform issues

- `terraform plan` wants to replace the instance after changing user-data:
  expected (`user_data_replace_on_change = true`).
- Bucket already exists errors: names are globally unique;
  `${project}-deploy-logs-${account_id}` is unique per account — if you
  renamed `project_name`, delete or import the old bucket first.
- Never commit `.terraform/`, `*.tfstate*` — they are git-ignored; if you
  accidentally committed state, rotate any secrets present and run
  `git rm --cached` before the next push.
