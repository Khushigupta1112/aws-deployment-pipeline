# Deployment Flow — What Actually Happens

Every step below maps to real code in this repository. Nothing on this page
is aspirational.

## Trigger

1. You run `git push origin main`.
2. The push event matches the `on.push.branches: [main]` trigger in
   `.github/workflows/deploy.yml` and GitHub starts a workflow run.
   (`workflow_dispatch` also allows manual runs from the Actions tab.)

## Job 1: `test`

| Step | What runs | Failure behavior |
| --- | --- | --- |
| Checkout | `actions/checkout@v4` clones the commit | stops workflow |
| Setup Node | `actions/setup-node@v4`, Node 24, npm cache keyed on `app/package-lock.json` | stops workflow |
| Install | `npm ci` in `app/` — reproducible install from the lockfile | stops workflow |
| Test | `npm test` → `vitest run` (8 tests across `/`, `/health`, `/ready`, 404s, config behavior) | **stops workflow — nothing deploys if tests fail** |

## Job 2: `deploy` (runs only after `test` succeeds)

1. **Resolve identifiers** — the account ID is extracted from the OIDC role
   ARN (`arn:aws:iam::<account>:role/...` → `cut -d: -f5`), and the ECR
   registry hostname is derived: `<account>.dkr.ecr.<region>.amazonaws.com`.
2. **AWS auth via OIDC** — `aws-actions/configure-aws-credentials@v4` exchanges
   the workflow's OIDC token for short-lived AWS credentials. The role's trust
   policy only allows `repo:<owner>/<repo>:ref:refs/heads/main`.
3. **ECR login** — `aws ecr get-login-password | docker login`.
4. **Build** — `docker build -f docker/Dockerfile --build-arg APP_VERSION=<7-char SHA>`.
   The SHA is baked into the image as `APP_VERSION`, so `/` reports exactly
   which commit is running.
5. **Push** — two tags pushed to ECR: `:<full commit sha>` (immutable record)
   and `:latest` (convenience pointer).
6. **SSH setup** — `webfactory/ssh-agent@v0.9.0` loads the deploy key from the
   `EC2_SSH_PRIVATE_KEY` secret.
7. **Upload scripts** — `scp` copies `scripts/deploy.sh`, `health-check.sh`,
   `rollback.sh` to `~/app/` on the host. Uploading every deploy means the
   host never runs stale scripts.
8. **Deploy** — `ssh ... ~/app/deploy.sh <full-sha>` runs on the EC2 host:
   - ECR login via the **instance role** (no credentials stored on the host)
   - `docker pull` the exact SHA tag
   - stop + remove the previous container (brief downtime window — see note)
   - run the new container on port 80 → 3000 with `--restart unless-stopped`
   - `health-check.sh` polls `http://127.0.0.1:3000/health` (15 attempts, 2s apart)
   - on success: records `.previous-image` / `.current-image` state files
   - on failure: prints container logs, removes the bad container, starts the
     previous image, re-verifies health, and exits non-zero either way
   - a non-zero exit fails the workflow (`needs: test` + step exit codes)
9. **Independent public verification** — the runner itself `curl`s the public
   IP: `jq` asserts `/health` says `healthy` and `/` reports `version` equal
   to the commit SHA that was just deployed.
10. **Deployment log** — a log object with commit SHA, message, author, actor,
    image, host, health-check result, and workflow run URL is written locally
    then uploaded to `s3://<bucket>/deployments/<YYYY-MM-DD>/<sha>.log`.
    This step runs with `if: always()` so **failed deployments leave a log too**.

## The brief downtime window (honest statement)

`deploy.sh` stops the old container before starting the new one, so there is
a gap of a few seconds during which port 80 refuses connections. This is an
**automated single-host deployment with health verification and rollback**,
not zero-downtime deployment. A real zero-downtime design needs at least an
ALB + two instances (or ECS rolling deploys) — that is listed under Future
Improvements, not implemented.

## Timing expectations

| Phase | Typical time |
| --- | --- |
| Checkout + npm ci | 30–60 s |
| Test suite | < 5 s |
| Docker build (cache hit) | 10–30 s |
| Docker build (cold) | 1–3 min |
| ECR push | 15–45 s |
| EC2 pull + start + health | 20–60 s |
| Total | 2–5 min |
