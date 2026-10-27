$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$id = [guid]::NewGuid().ToString('N').Substring(0,12)
$name = "agentdeck-m9-$id"
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

  # Copy companion python source into build context
  $serverSrc = Join-Path $repo 'server'
  Copy-Item -Path (Join-Path $serverSrc 'agentdeck_companion') -Destination (Join-Path $build 'agentdeck_companion') -Recurse -Force
  Copy-Item -Path (Join-Path $serverSrc 'agentdeck-companion') -Destination (Join-Path $build 'agentdeck-companion') -Force

  $dockerfile = @'
FROM alpine:3.21
ENV LANG=C.UTF-8 LC_ALL=C.UTF-8
RUN apk add --no-cache openssh git tmux procps coreutils util-linux python3 && adduser -D -s /bin/sh lab && mkdir -p /run/sshd /usr/local/lib/agentdeck /var/lib/agentdeck /etc/agentdeck
COPY entrypoint.sh /entrypoint.sh
COPY agentdeck-fake-agent /usr/local/bin/agentdeck-fake-agent
COPY agentdeck_companion /usr/local/lib/agentdeck/agentdeck_companion
COPY agentdeck-companion /usr/local/lib/agentdeck/agentdeck-companion
RUN chmod 700 /entrypoint.sh && chmod 755 /usr/local/bin/agentdeck-fake-agent && chmod 755 /usr/local/lib/agentdeck/agentdeck-companion && ln -sf /usr/local/lib/agentdeck/agentdeck-companion /usr/local/bin/agentdeck-companion && chown -R lab:lab /var/lib/agentdeck /etc/agentdeck
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
    sleep 4
    exit 1
    ;;
  *)
    echo "Unknown mode $1"
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

  $keyOut = docker exec $name ssh-keygen -l -f /etc/ssh/ssh_host_ed25519_key.pub
  if ($LASTEXITCODE -ne 0 -or $keyOut -notmatch 'SHA256:[A-Za-z0-9+/]{43}') { throw 'Failed to retrieve ed25519 host key fingerprint' }
  $fingerprint = $Matches[0]

  $env:AGENTDECK_TEST_SSH_HOST = '127.0.0.1'
  $env:AGENTDECK_TEST_SSH_PORT = $port
  $env:AGENTDECK_TEST_SSH_PASSWORD = $password
  $env:AGENTDECK_TEST_SSH_FINGERPRINT = $fingerprint
  $env:DOCKER_CONTAINER_NAME = $name

  Push-Location $repo
  try {
    & "C:\Users\vszni\sdk\flutter\bin\dart.bat" run tool/push_lab.dart
    if ($LASTEXITCODE -ne 0) { throw "Push Lab execution failed with exit code $LASTEXITCODE" }
  } finally {
    Pop-Location
  }
}
finally {
  if ($started) {
    docker stop -t 1 $name 2>$null | Out-Null
    docker rm -f $name 2>$null | Out-Null
  }
  if ($networkCreated) {
    docker network rm $network 2>$null | Out-Null
  }
  if ($built) {
    docker rmi -f $image 2>$null | Out-Null
  }
  if (Test-Path $labRoot) {
    Remove-Item -Path $labRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
