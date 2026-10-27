$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$id = [guid]::NewGuid().ToString('N').Substring(0,12)
$name = "agentdeck-m5-$id"
$network = "$name-net"
$image = "$name-image"
$labRoot = Join-Path $env:TEMP $name
$build = Join-Path $labRoot 'build'
$secrets = Join-Path $labRoot 'secrets'
$started = $false
$networkCreated = $false
$built = $false
try {
  New-Item -ItemType Directory -Path $build,$secrets -Force | Out-Null
  $dockerfile = @'
FROM alpine:3.21
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
RUN apk add --no-cache openssh tmux && adduser -D -s /bin/sh lab && mkdir -p /run/sshd
COPY entrypoint.sh /entrypoint.sh
COPY agentdeck-fake-agent /usr/local/bin/agentdeck-fake-agent
RUN chmod 700 /entrypoint.sh && chmod 755 /usr/local/bin/agentdeck-fake-agent
EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
'@ -replace "`r`n", "`n"
  [System.IO.File]::WriteAllText((Join-Path $build 'Dockerfile'), $dockerfile, [System.Text.UTF8Encoding]::new($false))

  $fakeAgent = @'
#!/bin/sh
set -e

case "${1:-running}" in
  --version|-v)
    echo "agentdeck-fake-agent 1.0.0-lab"
    exit 0
    ;;
  running)
    echo "[RUNNING] Fake agent started in running mode."
    while true; do
      sleep 1
    done
    ;;
  waiting)
    echo "[WAITING_USER] Please provide user instruction:"
    read -r line
    echo "[RUNNING] User instructed: $line"
    while true; do
      sleep 1
    done
    ;;
  success)
    echo "[RUNNING] Processing task..."
    echo "[FINISHED] Completed successfully."
    sleep 2
    exit 0
    ;;
  fail)
    echo "[RUNNING] Processing task..."
    echo "[FAILED] Error occurred."
    sleep 2
    exit 1
    ;;
  *)
    echo "Usage: agentdeck-fake-agent [--version|running|waiting|success|fail]"
    exit 1
    ;;
esac
'@ -replace "`r`n", "`n"
  [System.IO.File]::WriteAllText((Join-Path $build 'agentdeck-fake-agent'), $fakeAgent, [System.Text.UTF8Encoding]::new($false))

  $entrypoint = @'
#!/bin/sh
set -eu
cat /lab/password | chpasswd
ssh-keygen -A >/dev/null
exec /usr/sbin/sshd -D -e -o PermitRootLogin=no -o PasswordAuthentication=yes -o PubkeyAuthentication=no -o AllowUsers=lab
'@ -replace "`r`n", "`n"
  [System.IO.File]::WriteAllText((Join-Path $build 'entrypoint.sh'), $entrypoint, [System.Text.UTF8Encoding]::new($false))

  $bytes = New-Object byte[] 24
  $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
  $password = [Convert]::ToBase64String($bytes)
  [System.IO.File]::WriteAllText((Join-Path $secrets 'password'), "lab:$password`n", [System.Text.UTF8Encoding]::new($false))

  docker build -q -t $image $build | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Docker image build failed' }
  $built = $true

  docker network create --driver bridge $network | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Docker network creation failed' }
  $networkCreated = $true

  docker run -d --name $name --network $network -p '127.0.0.1::22' --mount "type=bind,source=$secrets,target=/lab,readonly" --pids-limit 128 --memory 256m --cpus 1 $image | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Docker sshd start failed' }
  $started = $true

  Start-Sleep -Seconds 2
  $binding = docker port $name '22/tcp'
  if ($LASTEXITCODE -ne 0 -or $binding -notmatch '^127\.0\.0\.1:(\d+)$') { throw 'Unsafe or unavailable port binding' }
  $port = $Matches[1]

  $fingerprint = $null
  for ($i = 0; $i -lt 15; $i++) {
    $keyLine = docker exec $name ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub 2>$null
    if ($LASTEXITCODE -eq 0 -and $keyLine -match '(SHA256:[A-Za-z0-9+/]{43})') {
      $fingerprint = $Matches[1]
      break
    }
    Start-Sleep -Milliseconds 500
  }
  if (-not $fingerprint) { throw 'Host fingerprint unavailable' }

  Start-Sleep -Milliseconds 500
  Write-Output "Local lab: $name, 127.0.0.1:$port"

  $env:AGENTDECK_TEST_SSH_HOST = '127.0.0.1'
  $env:AGENTDECK_TEST_SSH_PORT = $port
  $env:AGENTDECK_TEST_SSH_PASSWORD = $password
  $env:AGENTDECK_TEST_SSH_FINGERPRINT = $fingerprint

  $flutterBin = 'C:\Users\vszni\sdk\flutter\bin'
  if (Test-Path -LiteralPath $flutterBin) { $env:Path = $flutterBin + ';' + $env:Path }

  Push-Location $repo
  try {
    & dart run tool/agents_lab.dart
    if ($LASTEXITCODE -ne 0) { throw 'Agents lab scenarios failed' }
  } finally { Pop-Location }
} finally {
  Remove-Item Env:AGENTDECK_TEST_SSH_PASSWORD,Env:AGENTDECK_TEST_SSH_FINGERPRINT,Env:AGENTDECK_TEST_SSH_HOST,Env:AGENTDECK_TEST_SSH_PORT -ErrorAction SilentlyContinue
  if ($started) { docker rm -f $name | Out-Null }
  if ($networkCreated) { docker network rm $network | Out-Null }
  if ($built) { docker image rm $image | Out-Null }
  $tempResolved = [System.IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
  $targetResolved = [System.IO.Path]::GetFullPath($labRoot)
  if ($targetResolved.StartsWith($tempResolved + '\', [System.StringComparison]::OrdinalIgnoreCase) -and
      [System.IO.Path]::GetFileName($targetResolved) -eq $name -and
      $name -match '^agentdeck-m5-[0-9a-f]{12}$') {
    Remove-Item -LiteralPath $targetResolved -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Output "Lab cleanup attempted: $name"
}
