# Native Windows execution of the exact packaged evaluator. No physical GPU claim.
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$Evidence = Join-Path $RepoRoot 'build/windows-evidence'
$Runtime = Join-Path $RepoRoot '.runtime'
New-Item -ItemType Directory -Force -Path $Evidence | Out-Null
$Steps = [System.Collections.Generic.List[object]]::new()
$DriverRegistryKey = $null
$DriverRegistryName = ''
$DriverRegistryHadValue = $false
$DriverRegistryPriorValue = $null
$DriverRegistryPriorKind = $null
$Qualification = [ordered]@{
    schema = 'xenovection.windows-qualification.v1'
    status = 'RUNNING'
    platform = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    physical_gpu_qualified = $false
    scope = 'Native Windows executable, Vulkan Forward+ with pinned Mesa software rendering'
    vsync_requested = 'Disabled; any driver fallback is recorded per scene from the engine log'
    profile_scope = 'Short software Windows qualification: 60 measured frames after 60 warm-up frames; screenshot readback precedes measurement'
    owner_titan_rtx_qualification = 'Pending owner hardware execution and visual acceptance'
    steps = $Steps
    scenes = @()
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Executable,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 300,
        [string]$EngineLog = ''
    )
    $Log = Join-Path $Evidence ($Name + '.log')
    $Start = [System.Diagnostics.ProcessStartInfo]::new()
    $Start.FileName = $Executable
    $Start.WorkingDirectory = $RepoRoot
    $Start.UseShellExecute = $false
    $Start.RedirectStandardOutput = $true
    $Start.RedirectStandardError = $true
    foreach ($Argument in $Arguments) { $Start.ArgumentList.Add($Argument) }
    $Process = [System.Diagnostics.Process]::new()
    $Process.StartInfo = $Start
    $Timer = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "Running $Name"
    if (-not $Process.Start()) { throw "Could not start $Name" }
    $OutputTask = $Process.StandardOutput.ReadToEndAsync()
    $ErrorTask = $Process.StandardError.ReadToEndAsync()
    $Finished = $Process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $Finished) { $Process.Kill($true); $Process.WaitForExit() }
    $OutputText = $OutputTask.GetAwaiter().GetResult() + $ErrorTask.GetAwaiter().GetResult()
    $OutputText | Set-Content -Encoding utf8 -Path $Log
    $InspectText = $OutputText
    if ($EngineLog -and (Test-Path -LiteralPath $EngineLog)) {
        $InspectText += "`n" + (Get-Content -Raw -LiteralPath $EngineLog)
    }
    $ExitCode = $Process.ExitCode
    $HasEngineError = $InspectText -match '(?m)(SCRIPT ERROR:|Parse Error:|Shader compilation failed|^ERROR:)'
    $Passed = $Finished -and $ExitCode -eq 0 -and -not $HasEngineError
    $Steps.Add([ordered]@{
        name = $Name; status = $(if ($Passed) { 'PASS' } else { 'FAIL' })
        executable = $Executable; arguments = $Arguments; exit_code = $ExitCode
        elapsed_seconds = [Math]::Round($Timer.Elapsed.TotalSeconds, 3)
        timeout = -not $Finished; engine_error_detected = $HasEngineError
        log = (Split-Path -Leaf $Log)
    })
    $Process.Dispose()
    Write-Host $OutputText
    if (-not $Passed) { throw "$Name failed (exit $ExitCode; timeout=$(-not $Finished); engine_error=$HasEngineError). See $Log" }
}

function Assert-FileHash {
    param([string]$Path, [string]$Expected)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
    $Actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
    if ($Actual -ne $Expected.ToLowerInvariant()) { throw "SHA-256 mismatch: $Path" }
}

function Read-PngDimensions {
    param([string]$Path)
    $Bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($Bytes.Length -lt 10000 -or [Convert]::ToHexString([byte[]]$Bytes[0..7]) -ne '89504E470D0A1A0A') {
        throw "Missing or invalid rendered PNG: $Path"
    }
    $WidthBytes = [byte[]]$Bytes[16..19]
    $HeightBytes = [byte[]]$Bytes[20..23]
    [Array]::Reverse($WidthBytes); [Array]::Reverse($HeightBytes)
    $Width = [BitConverter]::ToUInt32($WidthBytes, 0)
    $Height = [BitConverter]::ToUInt32($HeightBytes, 0)
    if ($Width -lt 640 -or $Height -lt 360) { throw "Unexpected screenshot dimensions: $Width x $Height" }
    return @($Width, $Height)
}

function Write-TreeEvidence {
    param([string]$Stage)
    $StatusText = (& git -C $RepoRoot status --porcelain --untracked-files=no | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect source working tree' }
    $DiffText = (& git -C $RepoRoot diff --no-ext-diff --binary | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect source diff' }
    $StatusText | Set-Content -Encoding utf8 (Join-Path $Evidence ($Stage + '-git-status.log'))
    $DiffText | Set-Content -Encoding utf8 (Join-Path $Evidence ($Stage + '-git-diff.log'))
    if ($StatusText.Trim()) {
        Write-Host "Tracked source changes at ${Stage}:"
        Write-Host $StatusText
        Write-Host $DiffText.Substring(0, [Math]::Min(6000, $DiffText.Length))
    }
}

try {
    if (-not $IsWindows) { throw 'This harness must run on native Windows.' }
    $SourceSha = (& git -C $RepoRoot rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0 -or $SourceSha -notmatch '^[0-9a-f]{40}$') { throw 'Cannot identify source revision' }
    $Qualification.source_sha = $SourceSha
    Write-TreeEvidence -Stage 'initial'
    Invoke-Checked -Name 'prepare-runtime' -Executable 'python' -Arguments @(
        (Join-Path $RepoRoot 'tools/prepare_runtime.py'), '--runtime', $Runtime, '--evidence', $Evidence
    ) -TimeoutSeconds 1200
    $Tools = Get-Content -Raw (Join-Path $Runtime 'runtime.json') | ConvertFrom-Json
    $Editor = [string]$Tools.paths.godot_console
    $env:VK_ICD_FILENAMES = [string]$Tools.paths.icd
    $env:VK_DRIVER_FILES = [string]$Tools.paths.icd
    $env:PATH = [string]$Tools.paths.mesa + ';' + $env:PATH
    $env:LP_NUM_THREADS = '4'
    # The recovered historical verifier is kept unchanged, including NumPy use.
    Invoke-Checked -Name 'numerical-dependency' -Executable 'python' -Arguments @('-m', 'pip', 'install', '--disable-pip-version-check', 'numpy==2.2.6')
    Invoke-Checked -Name 'historical-numerical' -Executable 'python' -Arguments @(
        (Join-Path $RepoRoot 'experiments/found-001/source/tests/verify_specimen.py')
    )
    # Godot import is allowed to generate metadata only in a disposable extraction.
    # The recovered archive and preserved source tree remain untouched.
    $HistoricalArchive = Join-Path $RepoRoot 'experiments/found-001/FRANKENFIELD-FOUND-001-Godot47-FIXED.zip'
    Assert-FileHash -Path $HistoricalArchive -Expected 'ebb3df3a271cdd2e3294d812392e4e5d03d666761d1f5ee8d5b5c90f3954d362'
    $HistoricalCopy = Join-Path $RepoRoot 'build/historical-startup'
    if (Test-Path $HistoricalCopy) { Remove-Item -Recurse -Force $HistoricalCopy }
    Expand-Archive -LiteralPath $HistoricalArchive -DestinationPath $HistoricalCopy
    $HistoricalProject = Join-Path $HistoricalCopy 'frankenfield_fieldstudy_001'
    Assert-FileHash -Path (Join-Path $HistoricalProject 'data/synthetic_foundry.json') -Expected '745d47fa3ebd6a91ce1c9bd11181688ce4237199bbbce11e2e330dc76d78947c'
    Invoke-Checked -Name 'historical-godot-import' -Executable $Editor -Arguments @('--headless', '--path', $HistoricalProject, '--editor', '--import')
    Invoke-Checked -Name 'historical-godot-startup' -Executable $Editor -Arguments @('--headless', '--path', $HistoricalProject, '--quit-after', '10')
    Write-TreeEvidence -Stage 'after-historical-import'
    Invoke-Checked -Name 'editor-import' -Executable $Editor -Arguments @('--headless', '--path', (Join-Path $RepoRoot 'app'), '--editor', '--import')
    Write-TreeEvidence -Stage 'after-app-import'
    $Tests = [ordered]@{
        'core-contracts' = (Join-Path $RepoRoot 'tests/test_core.gd')
        'integrated-contracts' = (Join-Path $RepoRoot 'tests/test_integration.gd')
        'ecology-contracts' = (Join-Path $RepoRoot 'tests/test_ecology.gd')
        'filament-contracts' = 'res://rendering/filaments/verify_filaments.gd'
        'optical-contracts' = 'res://rendering/optical/verify_optical.gd'
    }
    foreach ($Test in $Tests.GetEnumerator()) {
        Invoke-Checked -Name $Test.Key -Executable $Editor -Arguments @('--headless', '--path', (Join-Path $RepoRoot 'app'), '--script', $Test.Value)
    }
    Invoke-Checked -Name 'source-binary64-exactness' -Executable 'python' -Arguments @(
        (Join-Path $RepoRoot 'tests/verify_source_exact.py'), '--godot', $Editor,
        '--receipt', (Join-Path $Evidence 'source-binary64-exactness.json')
    )
    Write-TreeEvidence -Stage 'after-tests'
    Invoke-Checked -Name 'package' -Executable 'python' -Arguments @(
        (Join-Path $RepoRoot 'tools/package_evaluator.py'), '--godot', $Editor,
        '--templates', [string]$Tools.paths.templates, '--source-sha', $SourceSha,
        '--output', (Join-Path $RepoRoot 'build'), '--skip-tests'
    ) -TimeoutSeconds 600

    $PackageReceipt = Get-Content -Raw (Join-Path $RepoRoot 'build/package-receipt.json') | ConvertFrom-Json
    if ($PackageReceipt.build.source_sha -ne $SourceSha) { throw 'Package source identity mismatch' }
    $Archive = Join-Path $RepoRoot ('build/' + $PackageReceipt.archive)
    Assert-FileHash -Path $Archive -Expected $PackageReceipt.sha256
    $TestRoot = Join-Path $RepoRoot 'build/windows-test-copy'
    if (Test-Path $TestRoot) { Remove-Item -Recurse -Force $TestRoot }
    Expand-Archive -LiteralPath $Archive -DestinationPath $TestRoot
    $Payload = Join-Path $TestRoot 'Xenovection'
    $PayloadHashes = Get-Content -Raw (Join-Path $Payload 'SHA256SUMS.json') | ConvertFrom-Json -AsHashtable
    foreach ($Relative in $PayloadHashes.Keys) {
        if ($Relative -match '(^|/)\.\.(/|$)' -or [System.IO.Path]::IsPathRooted($Relative)) { throw 'Invalid payload hash path' }
        Assert-FileHash -Path (Join-Path $Payload $Relative) -Expected $PayloadHashes[$Relative]
    }
    foreach ($Forbidden in @('vulkan-1.dll', 'vulkan_lvp.dll', 'opengl32.dll')) {
        if (Test-Path (Join-Path $Payload $Forbidden)) { throw "CI graphics shim leaked into owner package: $Forbidden" }
    }
    $Qualification.package = $PackageReceipt
    $Qualification.verified_payload_files = $PayloadHashes.Count
    # Only the disposable extracted test copy receives the CI software loader.
    Copy-Item -LiteralPath ([string]$Tools.paths.loader) -Destination (Join-Path $Payload 'vulkan-1.dll')
    # The Khronos loader intentionally ignores ICD environment overrides at high
    # Windows integrity. Hosted runneradmin uses that token. Use documented
    # software-driver discovery instead, restoring only our own registry value.
    # This is restricted to the disposable hosted CI machine, never owner setup.
    $Principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $Elevated = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $Qualification.runner_elevated = $Elevated
    $Qualification.icd_discovery = 'Explicit process environment'
    if ($Elevated) {
        if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Elevated local execution is unsupported; run this harness without elevation.' }
        $DriverRegistryKey = [Microsoft.Win32.Registry]::LocalMachine.CreateSubKey('SOFTWARE\Khronos\Vulkan\Drivers', $true)
        $DriverRegistryName = [string]$Tools.paths.icd
        $DriverRegistryHadValue = $DriverRegistryKey.GetValueNames() -contains $DriverRegistryName
        if ($DriverRegistryHadValue) {
            $DriverRegistryPriorValue = $DriverRegistryKey.GetValue($DriverRegistryName)
            $DriverRegistryPriorKind = $DriverRegistryKey.GetValueKind($DriverRegistryName)
        }
        $DriverRegistryKey.SetValue($DriverRegistryName, 0, [Microsoft.Win32.RegistryValueKind]::DWord)
        $Qualification.icd_discovery = 'Temporary hosted-CI HKLM software-driver registration; restored in finally'
    }
    $env:VK_LOADER_DEBUG = 'error,warn,driver'
    Invoke-Checked -Name 'vulkan-preflight' -Executable 'python' -Arguments @(
        (Join-Path $RepoRoot 'tools/prepare_runtime.py'), '--runtime', $Runtime,
        '--evidence', $Evidence, '--probe-vulkan'
    )
    $Application = Join-Path $Payload 'Xenovection.exe'
    $Graphics = @('--rendering-method', 'forward_plus', '--rendering-driver', 'vulkan', '--audio-driver', 'Dummy', '--disable-vsync', '--windowed', '--resolution', '1000x650')
    Invoke-Checked -Name 'filament-vulkan-buffer-roundtrip' -Executable ([string]$Tools.paths.godot) -Arguments (
        $Graphics + @('--path', (Join-Path $RepoRoot 'app'), '--script', 'res://rendering/filaments/verify_filaments.gd', '--log-file', (Join-Path $Evidence 'filament-vulkan-engine.log'))
    ) -EngineLog (Join-Path $Evidence 'filament-vulkan-engine.log')

    foreach ($Preset in @('scientific', 'filaments', 'optical', 'hybrid', 'membrane', 'flow')) {
        $ProfilePath = Join-Path $Evidence ($Preset + '.json')
        $CapturePath = Join-Path $Evidence ($Preset + '.png')
        $EngineLog = Join-Path $Evidence ($Preset + '-engine.log')
        Invoke-Checked -Name ($Preset + '-playable-vulkan') -Executable $Application -Arguments (
            $Graphics + @('--log-file', $EngineLog, '--', "--preset=$Preset", '--hide-panel',
                '--warmup=60', '--profile-frames=60', "--profile=$ProfilePath",
                '--capture-frame=45', "--capture=$CapturePath")
        ) -TimeoutSeconds 240 -EngineLog $EngineLog
        $Profile = Get-Content -Raw $ProfilePath | ConvertFrom-Json
        $Dimensions = Read-PngDimensions -Path $CapturePath
        $VSyncFallback = (Get-Content -Raw -LiteralPath $EngineLog) -match 'Falling back to V-Sync mode Enabled'
        if ($Profile.render_target_pixels[0] -ne $Dimensions[0] -or $Profile.render_target_pixels[1] -ne $Dimensions[1]) {
            throw "Rendered pixel dimensions disagree with the profile: $Preset"
        }
        if ($Profile.platform.os -ne 'Windows' -or $Profile.platform.headless -or
            $Profile.platform.driver -ne 'vulkan' -or $Profile.platform.rendering_method -ne 'forward_plus' -or
            -not $Profile.platform.software_device) { throw "Unexpected graphics platform in $Preset" }
        if ($Profile.samples -lt 60 -or $Profile.draw_calls_3d -lt 1 -or $Profile.wall_frame.p50_ms -le 0 -or
            -not $Profile.source_unchanged -or $Profile.build.source_sha -ne $SourceSha -or $Profile.preset -ne $Preset) {
            throw "Incomplete or inconsistent packaged execution: $Preset"
        }
        if ($Preset -eq 'flow') {
            if ($Profile.source.source_id -ne 'xenovection-spatial-flow-v1' -or $Profile.source.node_count -ne 4608 -or $Profile.source.edge_count -ne 6144) {
                throw 'Packaged spatial-flow source identity or topology is incorrect'
            }
        } elseif ($Profile.source.revision -ne ('sha256:' + $PackageReceipt.build.specimen_sha256) -or
            -not $Profile.source.historical_custody_verified -or $Profile.source.node_count -ne 288 -or $Profile.source.edge_count -ne 11520) {
            throw "Packaged historical source identity or topology is incorrect: $Preset"
        }
        if ($Preset -eq 'scientific' -and (-not $Profile.scientific -or $Profile.filaments.secondary_fibres -ne 0 -or
            $Profile.filaments.primary_edges -ne 11520 -or $Profile.filaments.segments_per_strand -ne 1 -or
            $Profile.optical.optical_visible -or $Profile.optical.sky_visible)) {
            throw 'Scientific profile did not expose exact primary topology with decorative passes disabled'
        }
        if ((@('filaments', 'flow') -contains $Preset) -and $Profile.filaments.secondary_fibres -lt 1) {
            throw "Kinetic preset has no decorative fibre pass: $Preset"
        }
        if ((@('optical', 'hybrid', 'membrane') -contains $Preset) -and (-not $Profile.optical.optical_visible -or
            $Profile.optical.proxy_source_edges -ne $Profile.selection.edge_ids.Count)) {
            throw "Materialised proxy lost selected source membership: $Preset"
        }
        if ($Preset -eq 'membrane' -and -not $Profile.optical.surface_translucent) {
            throw 'Membrane qualification did not exercise the alpha material variant'
        }
        $Qualification.scenes += [ordered]@{
            preset = $Preset; status = 'EXECUTED'; capture = (Split-Path -Leaf $CapturePath)
            capture_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $CapturePath).Hash.ToLowerInvariant()
            capture_dimensions = $Dimensions; profile = (Split-Path -Leaf $ProfilePath)
            samples = $Profile.samples; device = $Profile.platform.device
            presentation = $(if ($VSyncFallback) { 'VSync Enabled: driver fallback despite Disabled request' } else { 'Disabled requested; no driver fallback reported' })
            wall_p50_ms = $Profile.wall_frame.p50_ms; wall_p95_ms = $Profile.wall_frame.p95_ms
            draw_calls_3d = $Profile.draw_calls_3d; visible_strands = $Profile.filaments.visible_strands
            source_unchanged = $Profile.source_unchanged
        }
    }
    $Qualification.ecology = @()
    for ($PresetIndex = 0; $PresetIndex -lt 6; $PresetIndex++) {
        $Name = "ecosystem-$PresetIndex"
        $ProfilePath = Join-Path $Evidence ($Name + '.json')
        $CapturePath = Join-Path $Evidence ($Name + '.png')
        $EngineLog = Join-Path $Evidence ($Name + '-engine.log')
        Invoke-Checked -Name ($Name + '-extracted-vulkan') -Executable $Application -Arguments (
            $Graphics + @('--log-file', $EngineLog, '--', "--ecosystem=$PresetIndex", '--eco-steps=360',
                '--eco-clean', "--eco-profile=$ProfilePath", "--eco-capture=$CapturePath")
        ) -TimeoutSeconds 240 -EngineLog $EngineLog
        $Profile = Get-Content -Raw $ProfilePath | ConvertFrom-Json
        $Dimensions = Read-PngDimensions -Path $CapturePath
        if ($Profile.build.source_sha -ne $SourceSha -or $Profile.ecology_schema -ne 'xenovection.ecology.observations.v1' -or
            $Profile.configuration.preset -ne $PresetIndex -or $Profile.simulation.tick -ne 360 -or
            $Profile.simulation.population -gt 192 -or $Profile.samples -lt 59 -or $Profile.wall_frame.p50_ms -le 0 -or
            $Profile.platform.os -ne 'Windows' -or $Profile.platform.headless -or
            $Profile.platform.driver -ne 'vulkan' -or $Profile.platform.rendering_method -ne 'forward_plus' -or
            -not $Profile.platform.software_device -or $Profile.digest -notmatch '^[0-9a-f]{64}
    Assert-FileHash -Path $Archive -Expected $PackageReceipt.sha256
    $Qualification.status = 'PASS'
    $Qualification.visual_evidence = 'Six baseline and six ecology native Windows PNGs; retain for human visual review'
}
catch {
    $Qualification.status = 'FAIL'
    $Qualification.failure = $_.ToString()
    throw
}
finally {
    $CleanupFailure = $null
    if ($null -ne $DriverRegistryKey) {
        try {
            if ($DriverRegistryHadValue) {
                $DriverRegistryKey.SetValue($DriverRegistryName, $DriverRegistryPriorValue, $DriverRegistryPriorKind)
            } else {
                $DriverRegistryKey.DeleteValue($DriverRegistryName, $false)
            }
            $Qualification.icd_registration_restored = $true
        } catch {
            $Qualification.icd_registration_restored = $false
            $Qualification.status = 'FAIL'
            $CleanupFailure = $_
        } finally {
            $DriverRegistryKey.Dispose()
        }
    }
    $Qualification | ConvertTo-Json -Depth 20 | Set-Content -Encoding utf8 (Join-Path $Evidence 'qualification.json')
    if ($null -ne $CleanupFailure) { throw $CleanupFailure }
}
) {
            throw "Invalid extracted ecology profile: $Name"
        }
        if ($PresetIndex -eq 0 -and $Profile.simulation.segments -lt 1) { throw 'Mycelial topology missing' }
        if ($Profile.simulation.signal_mean -le 0) { throw "No shared signal in $Name" }
        $Qualification.ecology += [ordered]@{
            preset = $PresetIndex; status = 'EXECUTED'; capture = (Split-Path -Leaf $CapturePath)
            capture_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $CapturePath).Hash.ToLowerInvariant()
            capture_dimensions = $Dimensions; profile = (Split-Path -Leaf $ProfilePath)
            ticks = $Profile.simulation.tick; population = $Profile.simulation.population
            segments = $Profile.simulation.segments; digest = $Profile.digest
            wall_p50_ms = $Profile.wall_frame.p50_ms; wall_p95_ms = $Profile.wall_frame.p95_ms
            mode = '360 fixed steps in batches of four; software rendering; not wall-clock ecology throughput'
        }
    }
    # Independent extracted control: disable the complete inter-organism interaction path.
    $Control = Join-Path $Evidence 'ecosystem-vortex-control.json'
    $ControlLog = Join-Path $Evidence 'ecosystem-vortex-control-engine.log'
    Invoke-Checked -Name 'ecosystem-vortex-interaction-disabled' -Executable $Application -Arguments (
        $Graphics + @('--log-file', $ControlLog, '--', '--ecosystem=1', '--eco-steps=360', '--eco-no-interactions', '--eco-clean', "--eco-profile=$Control")
    ) -TimeoutSeconds 240 -EngineLog $ControlLog
    $Off = Get-Content -Raw $Control | ConvertFrom-Json
    $On = Get-Content -Raw (Join-Path $Evidence 'ecosystem-1.json') | ConvertFrom-Json
    if ($Off.build.source_sha -ne $SourceSha -or $Off.simulation.tick -ne 360 -or $Off.configuration.interactions -or
        $Off.simulation.signal_mean -ne 0 -or $Off.simulation.queries -ne 0 -or
        $Off.spatial_digest -eq $On.spatial_digest) { throw 'Extracted vortex interaction control failed' }
    # The release archive must still be the same bytes after qualification.
    Assert-FileHash -Path $Archive -Expected $PackageReceipt.sha256
    $Qualification.status = 'PASS'
    $Qualification.visual_evidence = 'Six rendered native Windows PNGs; retain for human visual review'
}
catch {
    $Qualification.status = 'FAIL'
    $Qualification.failure = $_.ToString()
    throw
}
finally {
    $CleanupFailure = $null
    if ($null -ne $DriverRegistryKey) {
        try {
            if ($DriverRegistryHadValue) {
                $DriverRegistryKey.SetValue($DriverRegistryName, $DriverRegistryPriorValue, $DriverRegistryPriorKind)
            } else {
                $DriverRegistryKey.DeleteValue($DriverRegistryName, $false)
            }
            $Qualification.icd_registration_restored = $true
        } catch {
            $Qualification.icd_registration_restored = $false
            $Qualification.status = 'FAIL'
            $CleanupFailure = $_
        } finally {
            $DriverRegistryKey.Dispose()
        }
    }
    $Qualification | ConvertTo-Json -Depth 20 | Set-Content -Encoding utf8 (Join-Path $Evidence 'qualification.json')
    if ($null -ne $CleanupFailure) { throw $CleanupFailure }
}
