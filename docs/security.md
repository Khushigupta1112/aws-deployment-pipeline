# Security Review

This document records the actual security posture of the repository, item by
item, matching the checklist used during the final audit.

## Credentials and secrets

| Check | Status | Where enforced |
| --- | --- | --- |
| No AWS keys hardcoded anywhere | ✅ | Credentials come from OIDC (CI) and the instance role (EC2). `grep` the repo: no access keys exist. |
| No private keys committed | ✅ | Deploy key lives only in the `EC2_SSH_PRIVATE_KEY` GitHub secret. `.gitignore` blocks `*.pem`-style accidents via the general pattern (never add one). |
| `.env` ignored | ✅ | `.gitignore` has `.env` / `.env.*` / `!.env.example`; only the template is tracked. |
| GitHub secrets used for all deploy values | ✅ | Region, role ARN, host, user, key, repo, bucket — all secrets. |
| No secrets printed in logs | ✅ | `deploy.sh` and the workflow print image tags, statuses, and public health output only. AWS credential steps use the official actions which mask credentials. |

## Network exposure

| Surface | Exposure | Justification / note |
| --- | --- | --- |
| TCP 80 | `0.0.0.0/0` | The demo needs to be reachable by browsers and the CI runner's verification curl. |
| TCP 22 | Your IP only (`ssh_allowed_cidr`) | Deliberately never `0.0.0.0/0`. If your ISP changes your IP, update the SG rule (see Troubleshooting). |
| TCP 3000 | NOT exposed | The container publishes `80:3000` only. Node listens inside Docker's internal network path; there is no separate route to 3000 from the internet. |
| HTTPS | Not implemented | Correctly claimed as such. HTTP only; see Future Improvements (ACM + ALB). |

## IAM

- EC2 **instance role** (not access keys) authorizes image pulls — `ecr:GetAuthorizationToken` plus the three pull operations, scoped to the single repository ARN. No S3 or CloudWatch permissions on the instance: logs are uploaded by CI, and basic EC2 metrics need no agent.
- The GitHub deploy role's trust policy is constrained to one repository and `refs/heads/main` via the `sub` condition — forks and other branches cannot mint credentials.
- Attached permissions are inline, hand-written policies. No `AdministratorAccess`, no managed full-access policies anywhere.
- Why instance roles beat static keys: credentials are auto-rotated by the EC2 service, never appear on disk, and can't be leaked via logs/screenshots. Static `AWS_ACCESS_KEY_ID` files in `~/.aws` are the #1 leaked-credential pattern.

## Container

- Image runs as the `node` user (`USER node` in the Dockerfile), not root.
- Multi-stage build means no dev dependencies, npm cache, tests, git metadata, or `.env` files in the final image (verified via `.dockerignore`).
- Docker `HEALTHCHECK` runs from inside the container and only touches `127.0.0.1`.

## Storage

- The deployment-log S3 bucket has all four public-access-block flags set, versioning on, SSE-S3 encryption, `BucketOwnerEnforced` (ACLs disabled), and a 90-day lifecycle expiration for cost control.
- Nothing secret is ever written into log objects: commit SHA, message, author, actor, image tag, host IP, status. (The EC2 host IP is in the log — acceptable for a demo; move to hashed/alias values if you publish logs.)

## Host

- SSH requires the key pair imported at setup; password auth is not enabled on AL2023 by default.
- IMDSv2 enforced (`HttpTokens=required`) on the EC2 instance.
- Docker daemon starts on boot; containers run with `--restart unless-stopped`.

## Dependencies

- `npm ci` installs from the lockfile only.
- ECR repository has `scan_on_push = true` (vulnerability scanning per push).
- Dependabot: add `.github/dependabot.yml` (snippet below) after the first push — it's a one-file addition; do enable it.

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: npm
    directory: /app
    schedule: { interval: weekly }
  - package-ecosystem: github-actions
    directory: /
    schedule: { interval: weekly }
```

## Known limitations (stated honestly)

- SSH key deployment is the current deployment transport. Migrating to AWS
  Systems Manager Session Manager (no inbound SSH at all) is the top future
  improvement.
- The OIDC role can read nothing and can only write `deployments/*` objects —
  but it can overwrite an existing object under that prefix. Content-arbitrated
  policies or per-run prefixes are overkill here; noted for completeness.
- No TLS, no WAF, no rate limiting — fine for a demo, unacceptable for a real
  public production service.
