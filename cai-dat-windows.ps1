# cai-dat-windows.ps1 — Cài và chạy ZaloCRM trên Windows bằng Docker Desktop.
#
# Cách dùng (PowerShell, trong thư mục dự án):
#   powershell -ExecutionPolicy Bypass -File .\cai-dat-windows.ps1
# Hoặc nhấp đúp file CAI-DAT-WINDOWS.bat.
#
# Script sẽ:
#   1. Kiểm tra Docker Desktop đã cài và đang chạy
#   2. Tạo .env từ .env.example (nếu chưa có) với secret ngẫu nhiên
#   3. docker compose up -d --build
#   4. Chờ app sẵn sàng rồi mở trình duyệt http://localhost:3080

# 'Continue': PowerShell 5.1 biến stderr của lệnh native (docker) thành lỗi chặn
# khi để 'Stop'; script tự kiểm tra $LASTEXITCODE sau mỗi lệnh docker.
$ErrorActionPreference = 'Continue'
Set-Location -Path $PSScriptRoot

function Write-Step($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "`n[LOI] $msg" -ForegroundColor Red; Read-Host 'Nhan Enter de thoat'; exit 1 }

function New-RandomHex([int]$bytes) {
  $buf = New-Object byte[] $bytes
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($buf)
  return -join ($buf | ForEach-Object { $_.ToString('x2') })
}

function Set-EnvLine([string[]]$lines, [string]$key, [string]$value) {
  $found = $false
  $out = foreach ($l in $lines) {
    if ($l -match "^$key=") { $found = $true; "$key=$value" } else { $l }
  }
  if (-not $found) { $out += "$key=$value" }
  return ,$out
}

# ── 1. Docker ────────────────────────────────────────────────────────────────
Write-Step 'Kiem tra Docker Desktop'
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  Fail 'Chua cai Docker Desktop. Tai tai https://www.docker.com/products/docker-desktop (chon WSL 2), cai xong khoi dong lai may.'
}
docker info *> $null
if ($LASTEXITCODE -ne 0) {
  Fail 'Docker Desktop chua chay. Mo Docker Desktop, cho den khi hien "Engine running" roi chay lai script.'
}
docker compose version *> $null
if ($LASTEXITCODE -ne 0) { Fail 'Khong tim thay "docker compose". Cap nhat Docker Desktop len ban moi.' }

# ── 2. .env ──────────────────────────────────────────────────────────────────
Write-Step 'Tao file cau hinh .env'
if (Test-Path .env) {
  Write-Host '.env da ton tai - giu nguyen.'
} else {
  if (-not (Test-Path .env.example)) { Fail 'Khong thay .env.example. Ban dang chay script ngoai thu muc du an?' }
  $lines = Get-Content .env.example -Encoding UTF8
  $minioPass = New-RandomHex 16
  $lines = Set-EnvLine $lines 'JWT_SECRET' (New-RandomHex 32)
  $lines = Set-EnvLine $lines 'ENCRYPTION_KEY' (New-RandomHex 16)
  $lines = Set-EnvLine $lines 'DB_PASSWORD' (New-RandomHex 12)
  $lines = Set-EnvLine $lines 'APP_URL' 'http://localhost:3080'
  # MinIO admin + S3 key dùng chung một cặp, phải khớp nhau
  $lines = Set-EnvLine $lines 'MINIO_ROOT_USER' 'zalocrm'
  $lines = Set-EnvLine $lines 'MINIO_ROOT_PASSWORD' $minioPass
  $lines = Set-EnvLine $lines 'S3_ACCESS_KEY' 'zalocrm'
  $lines = Set-EnvLine $lines 'S3_SECRET_KEY' $minioPass
  # Ghi UTF-8 không BOM, xuống dòng LF (an toàn cho container Linux)
  [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot '.env'), (($lines -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding $false))
  Write-Host 'Da tao .env voi mat khau/secret ngau nhien.'
}

# ── 3. Build & chạy ──────────────────────────────────────────────────────────
Write-Step 'Build va khoi chay (lan dau mat 3-10 phut)'
docker compose up -d --build
if ($LASTEXITCODE -ne 0) { Fail 'docker compose that bai. Xem log: docker compose logs' }

# ── 4. Chờ app ───────────────────────────────────────────────────────────────
Write-Step 'Cho ung dung san sang'
$url = 'http://localhost:3080'
$ready = $false
for ($i = 0; $i -lt 60; $i++) {
  try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
    if ($r.StatusCode -lt 500) { $ready = $true; break }
  } catch { }
  Start-Sleep -Seconds 3
}
docker compose ps
if ($ready) {
  Write-Host "`nHoan tat! Mo $url de tao tai khoan admin." -ForegroundColor Green
  Start-Process $url
} else {
  Write-Host "`nUng dung chua phan hoi. Xem log: docker compose logs app" -ForegroundColor Yellow
}
Read-Host 'Nhan Enter de dong'
