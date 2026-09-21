# Screenshots

Add screenshots here after you deploy — these are exactly the shots that
make the demo compelling:

| File | What to capture |
| --- | --- |
| `01-github-actions-run.png` | Green workflow run: tests, build, ECR push, deploy steps |
| `02-ecr-image.png` | Image tagged with the commit SHA in Amazon ECR |
| `03-app-version.png` | Browser on `/` showing the new version after a push |
| `04-s3-deployment-log.png` | The uploaded log object under `deployments/` |
| `05-cloudwatch-alarm.png` | Alarm in ALARM state after the CPU test |
| `06-sns-email.png` | The alert email and the confirmed subscription |

Keep each file small (< 1 MB) so the repository stays fast to clone.
