$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$id = [guid]::NewGuid().ToString('N').Substring(0,12)
$name = "agentdeck-m2-$id"
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
  @'
FROM alpine:3.21
RUN apk add --no-cache openssh && adduser -D -s /bin/sh lab && mkdir -p /run/sshd /home/lab/.ssh && chown lab:lab /home/lab/.ssh
COPY entrypoint.sh /entrypoint.sh
RUN chmod 700 /entrypoint.sh
EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]
'@ | Set-Content -LiteralPath (Join-Path $build 'Dockerfile') -Encoding utf8
  @'
#!/bin/sh
set -eu
cat /lab/password | chpasswd
cp /lab/authorized_keys /home/lab/.ssh/authorized_keys
chown -R lab:lab /home/lab/.ssh
chmod 700 /home/lab/.ssh
chmod 600 /home/lab/.ssh/authorized_keys
ssh-keygen -A >/dev/null
exec /usr/sbin/sshd -D -e -o PermitRootLogin=no -o PasswordAuthentication=yes -o PubkeyAuthentication=yes -o AllowUsers=lab
'@ | Set-Content -LiteralPath (Join-Path $build 'entrypoint.sh') -Encoding utf8
  $password = [Convert]::ToBase64String([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(24))
  [System.IO.File]::WriteAllText((Join-Path $secrets 'password'), "lab:$password`n", [System.Text.UTF8Encoding]::new($false))
  & ssh-keygen -q -t ed25519 -N '' -f (Join-Path $secrets 'lab_key')
  if ($LASTEXITCODE -ne 0) { throw 'LAB_ONLY key generation failed' }
  Copy-Item -LiteralPath (Join-Path $secrets 'lab_key.pub') -Destination (Join-Path $secrets 'authorized_keys')
  docker build -q -t $image $build | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Docker image build failed' }
  $built = $true
  docker network create --driver bridge $network | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Docker network creation failed' }
  $networkCreated = $true
  docker run -d --name $name --network $network -p '127.0.0.1::22' --mount "type=bind,source=$secrets,target=/lab,readonly" --pids-limit 64 --memory 128m --cpus 1 $image | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Docker sshd start failed' }
  $started = $true
  Start-Sleep -Seconds 2
  $binding = docker port $name '22/tcp'
  if ($LASTEXITCODE -ne 0 -or $binding -notmatch '^127\.0\.0\.1:(\d+)$') { throw 'Unsafe or unavailable port binding' }
  $port = $Matches[1]
  $keyLine = docker exec $name ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
  if ($LASTEXITCODE -ne 0 -or $keyLine -notmatch '(SHA256:[A-Za-z0-9+/]{43})') { throw 'Host fingerprint unavailable' }
  $fingerprint = $Matches[1]
  Write-Output "Local lab: $name, 127.0.0.1:$port"
  $env:AGENTDECK_TEST_SSH_HOST = '127.0.0.1'
  $env:AGENTDECK_TEST_SSH_PORT = $port
  $env:AGENTDECK_TEST_SSH_PASSWORD = $password
  $env:AGENTDECK_TEST_SSH_FINGERPRINT = $fingerprint
  $flutterBin = 'C:\Users\vszni\sdk\flutter\bin'
  if (Test-Path -LiteralPath $flutterBin) { $env:Path = $flutterBin + ';' + $env:Path }
  Push-Location $repo
  try {
    & dart run tool/terminal_lab.dart
    if ($LASTEXITCODE -ne 0) { throw 'Terminal lab scenarios failed' }
    $processList = docker exec $name ps -o user,args
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect remote shell cleanup' }
    if (($processList -join "`n") -match '(?m)^lab\s+.*(?:/bin/sh|\-sh)(?:\s|$)') {
      throw 'Remote lab shell remained after channel close'
    }
    Write-Output 'Remote shell process cleanup: PASS'
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
      $name -match '^agentdeck-m2-[0-9a-f]{12}$') {
    Remove-Item -LiteralPath $targetResolved -Recurse -Force -ErrorAction SilentlyContinue
  }
  Write-Output "Lab cleanup attempted: $name"
}
