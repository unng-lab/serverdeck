# Creates and removes ONLY its uniquely named local disposable container.
$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
$fixtureName = 'serverdeck-ssh-fixture-' + [Guid]::NewGuid().ToString('N')
try {
    docker build -t serverdeck-ssh-fixture:dev test/fixtures/ssh
    if ($LASTEXITCODE -ne 0) { throw 'SSH fixture build failed' }
    docker run -d --name $fixtureName --label serverdeck.disposable=true -p '127.0.0.1::22' serverdeck-ssh-fixture:dev | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'SSH fixture start failed' }
    $fixtureFingerprint = $null
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $keyLine = docker exec $fixtureName ssh-keygen -lf /tmp/fixture_host_ed25519_key.pub 2>$null
        if ($LASTEXITCODE -eq 0) { $fixtureFingerprint = ($keyLine -split '\s+')[1]; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $fixtureFingerprint) { throw 'Disposable fixture key unavailable' }
    $fixturePort = (docker inspect $fixtureName --format '{{(index (index .NetworkSettings.Ports "22/tcp") 0).HostPort}}').Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Fixture port unavailable' }
    flutter test integration_test/ssh_fixture_test.dart -d windows "--dart-define=FIXTURE_SSH_FINGERPRINT=$fixtureFingerprint" "--dart-define=FIXTURE_SSH_PORT=$fixturePort"
    if ($LASTEXITCODE -ne 0) { throw 'SSH integration failed' }
} finally {
    # Name was generated locally; no pre-existing container can match it.
    docker rm -f $fixtureName 2>$null | Out-Null
    Pop-Location
}
