# Interview Guide

Answer bank for the questions a technical interviewer will ask about this
project. Every answer matches the actual implementation — if you say
something in an interview that is on this page, you can point at the file
that proves it.

## AWS

**What is a VPC?**
A Virtual Private Cloud — a logically isolated network for my AWS resources,
defined by a CIDR range (mine is `10.0.0.0/16`). Nothing inside can be
reached from the internet unless I explicitly attach an Internet Gateway and
open routes/security-group paths. I provisioned it with Terraform
(`infra/terraform/networking.tf`).

**What makes a subnet public?**
One thing: its route table has a route for `0.0.0.0/0` pointing to an
Internet Gateway. (`map_public_ip_on_launch` also gives instances public
IPv4 addresses at launch, which is why my EC2 has one.) I explain this in the
README architecture section with the exact route.

**What is an Internet Gateway?**
A horizontally scaled, redundant AWS-managed component that lets traffic flow
between the VPC and the internet — north-south. Without it, my EC2 could not
pull from ECR or serve HTTP.

**Why no NAT Gateway?**
A NAT Gateway would let a *private* subnet reach the internet, and it costs
~$0.045/hour plus data charges — roughly $32+/month just by existing. My design
uses a single public subnet, so the EC2 reaches ECR directly through the IGW;
there is no private tier yet, so a NAT would be paying for capability I don't
use. Documented in `COST.md`.

**Why EC2 (and not Lambda/ECS)?**
I wanted to demonstrate a classic industry pattern: a long-running container
workload on a VM I fully control — Docker daemon, SSH deploys, health checks.
Lambda is event-driven pricing, not a long-running web server model; ECS/Fargate
would abstract away the mechanics I'm deliberately learning (host setup,
container lifecycle). EC2 t3.micro also keeps this on the Free Tier.

**Why ECR?**
It's AWS's private Docker registry, natively integrated: OIDC role for CI push,
instance role for EC2 pull, and IAM-secured without a third-party account
(Docker Hub/Quay would need PATs stored as secrets). Plus `scan_on_push`
gives per-image vulnerability scanning.

**Why S3 for logs?**
Durable, cheap, versioned, and naturally access-controlled. Deployment logs
are write-once artifacts — S3's object model fits perfectly. The CI role can
only `PutObject` under `deployments/*`.

**Why CloudWatch?** Basic EC2 metrics (CPU, status checks) are collected
automatically — no agent, no cost. Alarms on those metrics are the standard
way to detect host trouble.

**Why SNS?** Alarm → notification channel. Email subscription to my address;
CloudWatch alarms publish to it on ALARM and OK transitions.

## Networking

**What happens when someone accesses the application?**
Browser → DNS resolves the EC2 public IP → packet to `ip:80` → SG allows 80
from anywhere → routed via IGW to the instance → Docker's `80:3000` mapping
forwards to the container's port 3000 → Express answers `/` or `/health`.

**Why is port 80 public but 22 not?**
80 must be reachable by the public (that's the product). 22 is
infrastructure access — it should only be reachable by me. Open SSH on
`0.0.0.0/0` is the single most probed port on the internet; credential
stuffing bots hammer it constantly.

**What is a route table?** Per-subnet rules that decide where packets leaving
the subnet go — my public table sends everything (`0.0.0.0/0`) to the IGW.

**What is a security group?** A stateful instance-level firewall. I define
allowed ingress (80 from anywhere, 22 from my IP) and egress. Stateless in
return-direction semantics: replies to allowed traffic are allowed back out.

## IAM

**What is an IAM role?** An identity that can be *assumed* (by a service,
federated user, or OIDC principal) and which carries permissions — no static
password/keys of its own.

**Why an instance role?** The EC2 metadata service supplies temporary
credentials to the Docker client automatically — `aws ecr get-login-password`
just works, with nothing stored on disk and automatic rotation.

**Why not store access keys on EC2?** Long-lived keys are static: they leak
via logs, backups, screenshots, and get pasted into wrong places. Roles give
auto-rotating short-lived credentials, and deleting the role instantly revokes
access.

**Least privilege?** Grant the minimum actions on the minimum resources.
Concretely: the instance role has 4 `ecr` actions (1 on `*` because that's
how GetAuthorizationToken works, 3 scoped to my repo ARN) and nothing else.
The GitHub role additionally has `s3:PutObject` on `deployments/*` only.

## Docker

**Why Docker?** Identical runtime from my laptop → CI → EC2. The image IS the
artifact; "works on my machine" becomes "the machine doesn't matter".

**Image vs container?** Image = immutable filesystem snapshot + startup
config (built once per commit). Container = a running process instance
created from an image. I tag images with the commit SHA and run one
container from it.

**`.dockerignore`?** Keeps the build context small and clean — no
`node_modules`, `.git`, `.env`, docs, or Terraform files ever reach the
build stage. Both a security and a speed measure.

**Why non-root?** Compromise containment: a bug in my Express app running as
`node` can't rewrite system files or install rootkits. `USER node` in the
Dockerfile.

**Docker HEALTHCHECK?** A Docker-executed probe (`wget /health` every 30s)
independent of any orchestrator — `docker ps` shows healthy/unhealthy.

**What happens when a container crashes?** Docker restarts it
(`--restart unless-stopped`). If it crashes *during deploy*, `deploy.sh`'s
health check fails, removes it, and rolls back to the previous image.

## CI/CD

Walk the pipeline slowly and tie each hop to a file:
1. `git push origin main` → GitHub webhook event → Actions runner spins up
   (`.github/workflows/deploy.yml` triggers).
2. `npm ci` + `vitest run` — 8 tests. Fail here = no deploy.
3. OIDC token from GitHub → STS `AssumeRoleWithWebIdentity` → temporary AWS
   credentials (no stored keys).
4. `docker build` with `--build-arg APP_VERSION=<sha>`, tagged
   `:<full-sha>` + `:latest`.
5. `docker push` to ECR.
6. `ssh-agent` loads deploy key → `scp` scripts to EC2 → `ssh ./deploy.sh <sha>`.
7. On EC2: instance-role ECR login, pull exact image, stop/remove old
   container, run new one, poll `/health` locally.
8. Script exit code decides workflow result; runner also curls the public
   `/health` and asserts the served version equals the commit.
9. Workflow writes a metadata log and `aws s3 cp`s it to
   `s3://<bucket>/deployments/<date>/<sha>.log` — on success and failure.

## Monitoring

**What is CloudWatch?** AWS's metrics/logs/alarms service. I use two
`AWS/EC2` metric alarms: `CPUUtilization` > 70% (2×300s) and
`StatusCheckFailed` ≥ 1 (2×60s), both publishing to SNS.

**How did you test the alarm?** Controlled CPU load on the EC2 host (the
README warns it intentionally burns CPU), then observed: metric datapoints
rise → 2 evaluation periods pass → ALARM → SNS email. Recovery (OK email)
observed after stopping the load. Exact commands in README §Monitoring.

**What if the instance goes unhealthy?** The status-check alarm fires
within ~2 minutes and emails me. If the container (not the host) dies,
Docker's restart policy handles it; if a *deployment* fails,
`deploy.sh` rolls back and CI fails loudly.

## Reliability

**What happens if deployment fails?** Workflow fails (tests, ECR, SSH,
health — all exit-code driven). The always-on log upload records the
failure; the previous version continues serving after rollback.

**How does rollback work?** State files `.previous-image`/`.current-image`
track deployments. New image unhealthy → script removes it, starts the
previous image, re-verifies health. Also runnable manually:
`~/app/rollback.sh`. Single host, single container — no blue-green.

**Why isn't this blue-green?** Blue-green needs two independent
environments and a traffic switch (LB or DNS). I have one instance running
one container that gets replaced. I say "automated container deployment
with health verification and rollback", never "zero-downtime".

**What would you change for production?** ALB + ASG (real
zero-downtime), SSM instead of SSH, TLS via ACM/Route 53, central logging,
staging environment + approvals, container image signing.

## Security

**Where are credentials stored?** Nowhere persistent. CI uses OIDC→STS
temporary credentials; EC2 uses its instance role. GitHub holds secrets
(host, user, key, bucket, region, role ARN) — none are in the repo.

**How is SSH protected?** Key-based only, restricted in the SG to my IP;
the private key exists only as a GitHub secret. Limitation: SCP/SSH as the
deploy transport — SSM is the improvement path.

**How is S3 protected?** All public-access flags on, encryption on,
ACLs off, IAM-scoped writes only.

**What would you improve?** SSM (no SSH), TLS, Dependabot + image scanning
gates, least-privilege audit via IAM Access Analyzer.

## Terraform

**Why IaC?** The stack is reproducible from `terraform apply` — a fresh
account reaches the same state deterministically; drift is reviewable.

**What does Terraform manage here?** VPC/IGW/subnet/route table, SG, IAM
roles + policies + instance profile, GitHub OIDC provider + deploy role,
ECR repo, S3 log bucket (all security configs + lifecycle), SNS topic +
subscription + policy, two CloudWatch alarms, EC2 instance + key pair.

**What is state?** Terraform's map of "resources I created" — without it,
plan/apply can't know what exists. Mine is local (git-ignored); teams use a
versioned, locked S3 backend.

**Why not commit state?** It can contain secrets (resource attributes),
causes concurrent-apply corruption, and belongs in a locked backend, not Git.

## 60-second interview summary (memorize this shape)

"I built a GitHub Actions pipeline that tests an Express app, builds its
Docker image tagged by commit SHA, pushes to ECR, then SSH-deploys to an
EC2 Amazon Linux host that pulls and runs the new container, verifies
health via `/health`, and automatically rolls back to the previous image on
failure. Every deploy writes an audit log to S3. The whole infrastructure —
VPC, subnet, IGW, security group, IAM roles via GitHub OIDC, ECR, S3, SNS,
and CloudWatch alarms — is Terraform-provisioned. Basic EC2 metrics alarm
to SNS email. I know it's not blue-green; the honest upgrade path is ALB +
ASG, SSM replacing SSH, and TLS."
