[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Create','Enroll','Remove')][string]$Mode,
    [Parameter(Mandatory)][string]$FixtureRoot,
    [string]$WorkspaceId = ''
)
. "$PSScriptRoot/mcp-fixture.ps1"
$FixtureRoot = Resolve-McpFixtureRoot $FixtureRoot
$identity = Read-McpFixtureIdentity $FixtureRoot
$fixtureId = [string]$identity.fixtureId
$name = 'serverdeck-mcp-' + $fixtureId
$tag = $name + ':fixture'
# Refuse saved remote Docker contexts before any server API call.
$endpoint = Invoke-McpFixtureDocker @('context','inspect','--format','{{.Endpoints.docker.Host}}')
if ($endpoint -notin @('npipe:////./pipe/dockerDesktopLinuxEngine','npipe:////./pipe/docker_engine') -or
    ($env:DOCKER_HOST -and $env:DOCKER_HOST -notin @('npipe:////./pipe/dockerDesktopLinuxEngine','npipe:////./pipe/docker_engine'))) {
    throw 'A local disposable Docker Linux engine is required.'
}
if ((Invoke-McpFixtureDocker @('info','--format','{{.OSType}}')) -cne 'linux') {
    throw 'Docker Linux engine unavailable.'
}

if ($Mode -eq 'Create') {
    if (Test-Path -LiteralPath (Join-Path $FixtureRoot 'docker.json')) { throw 'Fixture already created.' }
    if (Invoke-McpFixtureDocker @('ps','-q')) { throw 'Use an otherwise idle disposable Docker engine.' }
    [void](Invoke-McpFixtureDocker @('build','--pull','--label',"serverdeck.mcp.fixture=$fixtureId",
        '-f',(Join-Path $McpFixtureRepository 'executor/ci/Dockerfile'),'-t',$tag,
        (Join-Path $McpFixtureRepository 'executor')) -TimeoutSeconds 1800)
    $container = Invoke-McpFixtureDocker @('run','-d','--name',$name,
        '--label',"serverdeck.mcp.fixture=$fixtureId",'--env',"SERVERDECK_FIXTURE_ID=$fixtureId",
        '--privileged','--cgroupns=host','--mount','type=bind,source=/sys/fs/cgroup,target=/sys/fs/cgroup',
        '--tmpfs','/run','--tmpfs','/run/lock','--publish','127.0.0.1::22',$tag)
    if ($container -cnotmatch '^[a-f0-9]{64}$') { throw 'Invalid owned container identity.' }
    $ready = $false
    for ($attempt = 0; $attempt -lt 90; $attempt++) {
        try {
            [void](Invoke-McpFixtureDocker @('exec',$container,'systemctl','is-active','--quiet','multi-user.target') -TimeoutSeconds 5)
            $ready = $true; break
        } catch { Start-Sleep -Seconds 1 }
    }
    if (-not $ready) { throw 'Owned systemd fixture did not start.' }
    $seed = Invoke-McpFixtureDocker @('exec',$container,'/usr/bin/python3','-I',
        '/opt/serverdeck-source/ci/fixture.py','prepare-ssh') | ForEach-Object { ConvertFrom-McpFixtureJson $_ }
    if ($seed.fixtureId -cne $fixtureId -or $seed.uid -ne 42001 -or
        $seed.hostFingerprint -cnotmatch '^SHA256:[A-Za-z0-9+/]{43}$') { throw 'Fixture seed identity mismatch.' }
    $inspect = (Invoke-McpFixtureDocker @('inspect','--type','container',$container) | ForEach-Object { ConvertFrom-McpFixtureJson $_ })[0]
    $port = $inspect.NetworkSettings.Ports.'22/tcp'[0]
    if ($inspect.Config.Labels.'serverdeck.mcp.fixture' -cne $fixtureId -or $port.HostIp -cne '127.0.0.1' -or
        [int]$port.HostPort -lt 1 -or [int]$port.HostPort -gt 65535) { throw 'Fixture endpoint mismatch.' }
    $seed | Add-Member -NotePropertyName address -NotePropertyValue '127.0.0.1'
    $seed | Add-Member -NotePropertyName port -NotePropertyValue ([int]$port.HostPort)
    Write-McpFixtureSeed $FixtureRoot $seed
    Write-McpFixtureDocument $FixtureRoot 'docker.json' ([ordered]@{
        format=1;fixtureId=$fixtureId;containerId=$container;imageId=$inspect.Image;
        name=$name;address='127.0.0.1';port=[int]$port.HostPort;hostFingerprint=$seed.hostFingerprint
    })
    Write-Output 'MCP_FIXTURE_CREATED'
    return
}

$inspect = (Invoke-McpFixtureDocker @('inspect','--type','container',$name) | ForEach-Object { ConvertFrom-McpFixtureJson $_ })[0]
if ($inspect.Name -cne ('/' + $name) -or $inspect.Config.Labels.'serverdeck.mcp.fixture' -cne $fixtureId -or
    $inspect.Id -cnotmatch '^[a-f0-9]{64}$') { throw 'Owned container proof refused.' }
if ($Mode -eq 'Enroll') {
    if ($WorkspaceId -cnotmatch '^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$') { throw 'Actual workspace UUID required.' }
    $result = Invoke-McpFixtureDocker @('exec',$inspect.Id,'/usr/bin/python3','-I',
        '/opt/serverdeck-source/ci/fixture.py','enroll','--workspace-id',$WorkspaceId) -TimeoutSeconds 180 | ForEach-Object { ConvertFrom-McpFixtureJson $_ }
    if ($result.fixtureId -cne $fixtureId -or $result.workspaceId -cne $WorkspaceId) { throw 'Enrollment result mismatch.' }
    Write-McpFixtureDocument $FixtureRoot 'enrolled.json' $result
    Write-Output 'MCP_FIXTURE_ENROLLED'
} else {
    [void](Invoke-McpFixtureDocker @('rm','--force','--volumes',$inspect.Id))
    $image = (Invoke-McpFixtureDocker @('image','inspect',$tag) | ForEach-Object { ConvertFrom-McpFixtureJson $_ })[0]
    if ($image.Config.Labels.'serverdeck.mcp.fixture' -cne $fixtureId -or $image.Id -cne $inspect.Image) {
        throw 'Owned image proof refused.'
    }
    [void](Invoke-McpFixtureDocker @('image','rm',$tag))
    Write-Output 'MCP_FIXTURE_REMOVED'
}
