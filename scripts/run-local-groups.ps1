param(
    [string]$GoExecutable = '',
    [string]$PythonExecutable = 'python',
    [string]$EnvtestAssets = '',
    [int[]]$Groups = @(1, 2, 3, 4, 5, 7)
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $GoExecutable) {
    $portableGo = Join-Path $projectRoot '.cache/tools/go/bin/go.exe'
    if (Test-Path $portableGo) { $GoExecutable = $portableGo }
    else { $GoExecutable = (Get-Command go -ErrorAction Stop).Source }
}
$env:PYTHON_EXECUTABLE = (Get-Command $PythonExecutable -ErrorAction Stop).Source
$env:GOMODCACHE = Join-Path $projectRoot '.cache/go-mod'
$env:GOCACHE = Join-Path $projectRoot '.cache/go-build'
$env:GOMAXPROCS = '2'
if ($EnvtestAssets) { $env:KUBEBUILDER_ASSETS = $EnvtestAssets }
elseif (-not $env:KUBEBUILDER_ASSETS) {
    $env:KUBEBUILDER_ASSETS = Join-Path $projectRoot '.cache/envtest/1.35.0/controller-tools/envtest'
}
$packages = @{
    1 = 'group1_algorithm_worker'
    2 = 'group2_prc_algorithm'
    3 = 'group3_prc_ngd_ngg'
    4 = 'group4_full_real_algorithm'
    5 = 'group5_prc_refresh_lifecycle'
    7 = 'group7_bond_topology_flow'
}
foreach ($group in $Groups) {
    if (-not $packages.ContainsKey($group)) { throw "Unknown group $group; repository has groups 1, 2, 3, 4, 5, 7." }
}
$runDirectory = Join-Path $projectRoot ('go_test_suites/results/local-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Force $runDirectory | Out-Null
$results = @()
Push-Location $projectRoot
try {
    # controller-runtime v0.23.1 sends Unix signals during envtest cleanup.
    # Use an isolated Windows-only module copy; never edit the module cache.
    $windowsWorkFile = ''
    if ($env:OS -eq 'Windows_NT' -and ($Groups | Where-Object { $_ -in @(3, 4, 5, 7) })) {
        $ErrorActionPreference = 'Continue'
        & $GoExecutable mod download sigs.k8s.io/controller-runtime 2>&1 | Out-Host
        $downloadExitCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($downloadExitCode -ne 0) { throw 'Cannot prepare controller-runtime Windows workaround.' }
        $module = (& $GoExecutable list -m -json sigs.k8s.io/controller-runtime | ConvertFrom-Json)
        if ($module.Version -ne 'v0.23.1') { throw 'Review the Windows envtest workaround for the new controller-runtime version.' }
        $source = Join-Path $module.Dir 'pkg/internal/testing/process/process.go'
        $original = [System.IO.File]::ReadAllText($source)
        if (-not $original.Contains('ps.Cmd.Process.Signal(syscall.SIGTERM)')) {
            throw 'Expected envtest signal code was not found; review the Windows workaround.'
        }
        $patched = $original.Replace('ps.Cmd.Process.Signal(syscall.SIGTERM)', 'ps.Cmd.Process.Kill()').Replace('ps.Cmd.Process.Signal(syscall.SIGKILL)', 'ps.Cmd.Process.Kill()')
        $patched = $patched -replace '(?m)^\s*"syscall"\r?\n', ''
        $moduleCopy = Join-Path $projectRoot ('.cache/envtest-windows/' + (Split-Path $runDirectory -Leaf) + '/controller-runtime')
        New-Item -ItemType Directory -Force (Split-Path $moduleCopy -Parent) | Out-Null
        Copy-Item -LiteralPath $module.Dir -Destination $moduleCopy -Recurse
        $patchedSource = Join-Path $moduleCopy 'pkg/internal/testing/process/process.go'
        [System.IO.File]::SetAttributes($patchedSource, [System.IO.FileAttributes]::Normal)
        [System.IO.File]::WriteAllText($patchedSource, $patched)
        [System.IO.File]::WriteAllText((Join-Path $runDirectory 'envtest-process-windows.go.txt'), $patched)
        $windowsWorkFile = Join-Path $runDirectory 'windows.go.work'
        $workspace = @('go 1.25.0', '', 'use (')
        foreach ($relativeModule in @('algorithm_server/go', 'go_test_suites', 'prc', 'topology_agent')) {
            $modulePath = [System.IO.Path]::GetFullPath((Join-Path $projectRoot $relativeModule))
            $workspace += '    ' + (ConvertTo-Json -InputObject $modulePath -Compress)
        }
        $workspace += ')'
        $workspace += 'replace sigs.k8s.io/controller-runtime => ' + (ConvertTo-Json -InputObject $moduleCopy -Compress)
        [System.IO.File]::WriteAllText($windowsWorkFile, ($workspace -join "`n"))
        Copy-Item -LiteralPath (Join-Path $projectRoot 'go.work.sum') -Destination ($windowsWorkFile + '.sum')
        $env:GOWORK = $windowsWorkFile
        Write-Host 'Windows envtest cleanup: isolated controller-runtime v0.23.1 copy using Process.Kill.'
    }
    @(
        "Go: $(& $GoExecutable version)"
        "Python: $(& $env:PYTHON_EXECUTABLE --version)"
        "Envtest assets: $env:KUBEBUILDER_ASSETS"
        "Windows test workspace: $windowsWorkFile"
        'Group6: absent from repository'
    ) | Set-Content -Encoding UTF8 (Join-Path $runDirectory 'environment.txt')
    foreach ($group in $Groups) {
        $log = Join-Path $runDirectory "group$group.log"
        $started = Get-Date
        Write-Host "Running group$group; log=$log"
        # Windows PowerShell otherwise promotes native stderr to terminating errors.
        $ErrorActionPreference = 'Continue'
        & $GoExecutable test -p=1 "./go_test_suites/$($packages[$group])" -run "^TestGroup${group}_" -v -count=1 -timeout=10m > $log 2>&1
        $testExitCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        Get-Content $log | Select-Object -Last 12 | Write-Host
        $results += [pscustomobject]@{
            group = $group
            exitCode = $testExitCode
            status = $(if ($testExitCode -eq 0) { 'PASS' } else { 'FAIL' })
            elapsedSeconds = [math]::Round(((Get-Date) - $started).TotalSeconds, 3)
            log = $log
        }
        $results | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $runDirectory 'summary.json')
    }
}
finally { Pop-Location }
Write-Host "Results: $runDirectory"
if ($results | Where-Object exitCode -NE 0) { exit 1 }
