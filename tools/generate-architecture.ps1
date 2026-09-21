# Generates docs/architecture.png (Windows PowerShell 5.1, System.Drawing).
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot
$outPath = Join-Path $root "docs\architecture.png"

$W = 1400; $H = 980
$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAlias
$g.Clear([System.Drawing.Color]::White)

$fTitle = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$fHead  = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$fBody  = New-Object System.Drawing.Font("Segoe UI", 9)
$fSmall = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)

$sf = New-Object System.Drawing.StringFormat
$sf.Alignment = [System.Drawing.StringAlignment]::Center
$sf.LineAlignment = [System.Drawing.StringAlignment]::Center

$penBox = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(44,62,80), 2)

function Draw-Box([int]$x, [int]$y, [int]$w, [int]$h, [string]$fill, [string[]]$lines) {
    $rect = New-Object System.Drawing.Rectangle($x, $y, $w, $h)
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($fill))
    $script:g.FillRectangle($brush, $rect)
    $script:g.DrawRectangle($script:penBox, $x, $y, $w, $h)
    $i = 0
    $lineH = 22.0
    $blockH = $lineH * $lines.Count
    # Short boxes: center the text block. Tall container boxes: anchor text at the top so it does not collide with inner boxes.
    if ($h -le 72) { $startY = $y + ($h - $blockH) / 2 } else { $startY = $y + 8 }
    foreach ($line in $lines) {
        $font = $script:fBody
        if ($i -eq 0 -and $lines.Count -gt 1) { $font = $script:fHead }
        $lineRect = New-Object System.Drawing.RectangleF($x, ($startY + $lineH * $i), $w, $lineH)
        $color = [System.Drawing.Color]::FromArgb(30, 40, 55)
        $textBrush = New-Object System.Drawing.SolidBrush($color)
        $fmt = $script:sf
        $script:g.DrawString($line, $font, $textBrush, $lineRect, $fmt)
        $i++
    }
}

function Draw-Arrow([int]$x1, [int]$y1, [int]$x2, [int]$y2, [string]$label) {
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(70,80,100), 2)
    $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::ArrowAnchor
    $script:g.DrawLine($pen, $x1, $y1, $x2, $y2)
    if ($label) {
        $mx = [Math]::Min($x1, $x2) + [Math]::Abs($x2 - $x1) / 2
        $my = [Math]::Min($y1, $y2) + [Math]::Abs($y2 - $y1) / 2
        $labelRect = New-Object System.Drawing.RectangleF([single]($mx - 90), [single]($my - 12), 180, 20)
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(90, 100, 120))
        $script:g.DrawString($label, $script:fSmall, $brush, $labelRect, $script:sf)
    }
}

# Title
$g.DrawString("Automated AWS Deployment Pipeline", $fTitle, (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(30,40,55))), 60, 20)

# --- CI/CD column (left) ---
Draw-Box 90 90 240 50  "236,240,244" @("Developer")
Draw-Arrow 210 140 210 190 "git push (main)"
Draw-Box 90 190 240 54 "236,240,244" @("GitHub")
Draw-Arrow 210 244 210 292
Draw-Box 60 292 300 216 "236,240,244" @("GitHub Actions", "deploy.yml")
Draw-Box 76 348 268 30 "255,255,255" @("tests: npm ci + vitest (8 tests)")
Draw-Box 76 386 268 30 "255,255,255" @("docker build (APP_VERSION=sha)")
Draw-Box 76 424 268 30 "255,255,255" @("push image (sha tag + latest)")
Draw-Arrow 210 508 210 570
Draw-Box 70 570 280 54 "255,243,224" @("Amazon ECR", "aws-deployment-demo:<sha>")
Draw-Box 70 700 280 64 "232,245,233" @("S3 deployment logs", "deployments/<date>/<sha>.log")
Draw-Arrow 210 624 210 700 "audit log"

# --- Compute column (middle) ---
Draw-Box 510 90 350 400 "232,245,233" @("Amazon EC2", "Amazon Linux 2023 + Docker (IAM instance role)")
Draw-Box 528 180 314 34 "255,255,255" @("Docker container: host port 80 -> 3000")
Draw-Box 528 222 314 30 "255,255,255" @("GET /  ->  version = commit SHA")
Draw-Box 528 260 314 30 "255,255,255" @("GET /health (liveness)  GET /ready")
Draw-Box 528 298 314 48 "255,255,255" @("deploy.sh:", "pull exact image -> swap -> health check -> rollback")
Draw-Box 528 354 314 30 "255,255,255" @("application logs: docker logs")
Draw-Arrow 360 400 510 290 "ssh / scp (deploy scripts)"
Draw-Arrow 350 597 660 490 "pull exact image <sha>"

# --- Monitoring column (right) ---
Draw-Box 960 90 380 120 "227,242,253" @("CloudWatch Alarms", "CPUUtilization > 70%  (2 x 300s)", "StatusCheckFailed >= 1  (2 x 60s)")
Draw-Arrow 860 240 960 150 "metrics"
Draw-Arrow 1120 210 1120 290 "alarm action"
Draw-Box 960 290 380 60 "243,229,245" @("SNS topic: aws-deployment-alerts")
Draw-Arrow 1120 354 1120 420 "notify"
Draw-Box 960 420 380 56 "253,237,237" @("Email notification", "(confirmed subscription)")

# Footer note
$footBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(120,130,150))
$g.DrawString("HTTP only (no HTTPS). No NAT Gateway, no ALB, no ASG - deliberate scope for a single-host demo.", $fSmall, $footBrush, 60, 900)

# Save via a temp file first: GDI+ fails if the target is locked by a
# previewer/OneDrive sync at save time. Retry the final copy to outlast
# transient OneDrive placeholder locks.
$tmpPath = Join-Path ([System.IO.Path]::GetTempPath()) ("arch-" + [System.Guid]::NewGuid().ToString("N") + ".png")
$bmp.Save($tmpPath, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

$copied = $false
for ($attempt = 1; $attempt -le 15 -and -not $copied; $attempt++) {
    try {
        Copy-Item -LiteralPath $tmpPath -Destination $outPath -Force -ErrorAction Stop
        $copied = $true
    } catch {
        Write-Output "Copy attempt $attempt failed: $($_.Exception.Message)"
        Start-Sleep -Seconds 2
    }
}
if ($copied) { Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue; Write-Output "Saved: $outPath" } else { Write-Output "FAILED; latest bitmap kept at: $tmpPath" }
Write-Output "Saved: $outPath"
