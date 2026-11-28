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
    profile_scope = 'Retained per-suite workloads plus 90 measured frames for integrated views after 60 warm-up frames; screenshots precede measurement; full 36000-frame structural soak is separate'
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
    $HasEngineError = $InspectText -match '(?m)(SCRIPT ERROR:|Parse Error:|Shader compilation failed|^ERROR:|ObjectDB instances leaked|resources still in use|RIDs of type)'
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

function Invoke-ExtractedScript {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ScriptName,
        [string[]]$EngineArguments = @('--headless'),
        [string[]]$UserArguments = @(),
        [int]$TimeoutSeconds = 600,
        [string]$EngineLog = ''
    )
    # Official release templates disable the editor-only --script path override.
    # The application bootstrap runs the exact embedded script on its SceneTree.
    Invoke-Checked -Name $Name -Executable $Application -Arguments (
        $EngineArguments + @('--', ('--qualification-script=' + $ScriptName)) + $UserArguments
    ) -TimeoutSeconds $TimeoutSeconds -EngineLog $EngineLog
    $DispatchLog = Get-Content -Raw (Join-Path $Evidence ($Name + '.log'))
    if ($DispatchLog -notmatch [regex]::Escape('XENOVECTION_QUALIFICATION_SCRIPT_STARTED ' + $ScriptName)) {
        throw "Extracted executable did not dispatch the requested qualification script: $ScriptName"
    }
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
        throw "Tracked source changed during qualification at $Stage"
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
    Invoke-Checked -Name 'ecology-world-parse' -Executable $Editor -Arguments @('--headless', '--path', (Join-Path $RepoRoot 'app'), '--check-only', '--script', 'res://ecology/world.gd')
    Invoke-Checked -Name 'ecology-workspace-parse' -Executable $Editor -Arguments @('--headless', '--path', (Join-Path $RepoRoot 'app'), '--check-only', '--script', 'res://ecology/workspace.gd')
    Invoke-Checked -Name 'ecology-gui-probe-parse' -Executable $Editor -Arguments @('--headless', '--path', (Join-Path $RepoRoot 'app'), '--check-only', '--script', (Join-Path $RepoRoot 'tests/gui_ecology_probe.gd'))

    $Tests = [ordered]@{
        'matter-contracts' = (Join-Path $RepoRoot 'tests/test_matter.gd')
        'core-contracts' = (Join-Path $RepoRoot 'tests/test_core.gd')
        'integrated-contracts' = (Join-Path $RepoRoot 'tests/test_integration.gd')
        'synth-contracts' = (Join-Path $RepoRoot 'tests/test_synth.gd')
        'ecology-contracts' = (Join-Path $RepoRoot 'tests/test_ecology.gd')
        'composition-contracts' = (Join-Path $RepoRoot 'tests/test_compositions.gd')
        'matter-optics-contracts' = (Join-Path $RepoRoot 'tests/test_matter_optics.gd')
        'spatial-ecology-contracts' = (Join-Path $RepoRoot 'tests/test_convergence_ecology.gd')
        'convergence-contracts' = (Join-Path $RepoRoot 'tests/test_convergence.gd')
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
    $SourceTree = (git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
    if ($PackageReceipt.build.source_sha -ne $SourceSha -or $PackageReceipt.build.tree_sha -ne $SourceTree) { throw 'Package source/tree identity mismatch' }
    $Archive = Join-Path $RepoRoot ('build/' + $PackageReceipt.archive)
    Assert-FileHash -Path $Archive -Expected $PackageReceipt.sha256
    $TestRoot = Join-Path $RepoRoot 'build/windows-test-copy'
    if (Test-Path $TestRoot) { Remove-Item -Recurse -Force $TestRoot }
    Expand-Archive -LiteralPath $Archive -DestinationPath $TestRoot
    $Payload = Join-Path $TestRoot 'Xenovection'
    $EmbeddedBuild = Get-Content -Raw (Join-Path $Payload 'BUILD.json') | ConvertFrom-Json
    if ($EmbeddedBuild.source_sha -ne $SourceSha -or $EmbeddedBuild.tree_sha -ne $SourceTree -or
        $EmbeddedBuild.mission -ne 'MAINLINE-CONVERGENCE-001') { throw 'Extracted BUILD identity mismatch' }
    $Qualification.embedded_build = $EmbeddedBuild
    $Qualification.source_tree = $SourceTree
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
    $Qualification.script_custody = Get-Content -Raw (Join-Path $Payload 'qualification/SOURCE.json') | ConvertFrom-Json -AsHashtable
    foreach ($Entry in $Qualification.script_custody.Values) {
        Assert-FileHash -Path (Join-Path $RepoRoot $Entry.source_path) -Expected $Entry.sha256
    }
    # Every core contract also runs from the independently extracted executable.
    # These are exact copied scripts from the committed source, not substitutes.
    foreach ($Script in @('test_core.gd', 'test_integration.gd', 'test_matter.gd', 'test_synth.gd',
        'test_ecology.gd', 'test_compositions.gd', 'test_matter_optics.gd', 'test_convergence_ecology.gd',
        'test_convergence.gd', 'verify_filaments.gd', 'verify_optical.gd')) {
        $ScriptTimeout = $(if ($Script -eq 'test_core.gd') { 60 } else { 600 })
        Invoke-ExtractedScript -Name ('extracted-' + $Script.Replace('.gd', '')) -ScriptName $Script -TimeoutSeconds $ScriptTimeout
    }
    Invoke-ExtractedScript -Name 'extracted-full-resource-soak' -ScriptName 'test_soak.gd' -UserArguments @(
        "--receipt=$(Join-Path $Evidence 'extracted-soak.json')"
    ) -TimeoutSeconds 900
    $ExtractedBits = Join-Path $Evidence 'extracted-source-f64.bin'
    Invoke-ExtractedScript -Name 'extracted-source-export' -ScriptName 'export_source_bits.gd' -UserArguments @(
        "--output=$ExtractedBits"
    )
    Invoke-Checked -Name 'extracted-source-binary64-exactness' -Executable 'python' -Arguments @(
        (Join-Path $RepoRoot 'tests/verify_source_exact.py'), '--bits', $ExtractedBits,
        '--receipt', (Join-Path $Evidence 'extracted-source-binary64-exactness.json')
    )
    Assert-FileHash -Path (Join-Path $Payload 'data/synthetic_foundry.json') -Expected $EmbeddedBuild.specimen_sha256
    # New material/interaction gates run first so a meaningful new shader or
    # authoring failure is diagnosed before the expensive scene populations.
    foreach ($Probe in @('material', 'spatial_ecology', 'convergence')) {
        $ProbePrefix = Join-Path $Evidence ('gui-' + $Probe)
        $ProbeLog = $ProbePrefix + '-engine.log'
        Invoke-ExtractedScript -Name ('extracted-graphical-' + $Probe) -ScriptName ('gui_' + $Probe + '_probe.gd') -EngineArguments (
            $Graphics + @('--log-file', $ProbeLog)
        ) -UserArguments @("--output-prefix=$ProbePrefix") -TimeoutSeconds 600 -EngineLog $ProbeLog
        $ProbeReceipt = Get-Content -Raw ($ProbePrefix + '.json') | ConvertFrom-Json
        if ($ProbeReceipt.status -ne 'PASS' -or $ProbeReceipt.checks -lt 15) {
            throw "Incomplete graphical interoperability receipt: $Probe"
        }
    }
    Invoke-Checked -Name 'filament-vulkan-buffer-roundtrip' -Executable ([string]$Tools.paths.godot) -Arguments (
        $Graphics + @('--path', (Join-Path $RepoRoot 'app'), '--script', 'res://rendering/filaments/verify_filaments.gd', '--log-file', (Join-Path $Evidence 'filament-vulkan-engine.log'))
    ) -EngineLog (Join-Path $Evidence 'filament-vulkan-engine.log')

    foreach ($Preset in @('scientific', 'filaments', 'optical', 'hybrid', 'membrane', 'stress', 'flow', 'optical_dichroic', 'optical_weather', 'optical_lens', 'optical_garden', 'optical_microfibres', 'optical_ecosystem')) {
        $ProfilePath = Join-Path $Evidence ($Preset + '.json')
        $CapturePath = Join-Path $Evidence ($Preset + '.png')
        $EngineLog = Join-Path $Evidence ($Preset + '-engine.log')
        $SceneTimeout = $(if ($Preset -eq 'stress') { 480 } else { 240 })
        Invoke-Checked -Name ($Preset + '-playable-vulkan') -Executable $Application -Arguments (
            $Graphics + @('--log-file', $EngineLog, '--', "--preset=$Preset", '--hide-panel',
                '--warmup=60', '--profile-frames=60', "--profile=$ProfilePath",
                '--capture-frame=45', "--capture=$CapturePath")
        ) -TimeoutSeconds $SceneTimeout -EngineLog $EngineLog
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
        } elseif ($Preset -eq 'stress') {
            if ($Profile.source.source_id -ne 'found-002-synthetic-96' -or $Profile.source.node_count -ne 576 -or
                $Profile.source.edge_count -ne 46080 -or $Profile.source.historical_custody_verified -or
                $Profile.filaments.primary_edges -ne 46080 -or $Profile.filaments.segments_per_strand -ne 16) {
                throw 'Packaged dense-interference source or authored stress workload is incorrect'
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
        if ($Preset.StartsWith('optical_') -and (-not $Profile.optical.optical_visible -or
            $Profile.optical.optical_matter_mix -lt 0.99 -or $Profile.optical.proxy_source_edges -ne $Profile.selection.edge_ids.Count)) {
            throw "Optical demonstrator did not exercise its authored material and source selection: $Preset"
        }
        if ($Preset -eq 'optical_lens' -and -not $Profile.optical.refraction_screen_copy_active) {
            throw 'Liquid Lens did not exercise screen-copy refraction'
        }
        if ((@('optical_dichroic', 'optical_garden', 'optical_ecosystem') -contains $Preset) -and $Profile.optical.secondary_film_draws -ne 1) {
            throw "Layered optical scene did not render its second film: $Preset"
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
    # SYNTH-002 source GUI input probe and exact extracted-package patch profiles.
    $GuiPrefix = Join-Path $Evidence 'synth-gui'
    Invoke-ExtractedScript -Name 'synth-graphical-input' -ScriptName 'gui_synth_probe.gd' -EngineArguments (
        $Graphics + @('--log-file', (Join-Path $Evidence 'synth-gui-engine.log'))
    ) -UserArguments @("--output-prefix=$GuiPrefix") -TimeoutSeconds 300 -EngineLog (Join-Path $Evidence 'synth-gui-engine.log')
    $null = Read-PngDimensions -Path ($GuiPrefix + '.png')
    $Qualification.synth_patches = @()
    $PatchNames = @('Vortex Conductor', 'Weather Instrument', 'Filament Sequencer', 'Spectral Layers', 'Autonomous Organism', 'XY Morphosis')
    $PatchPresets = @('flow', 'membrane', 'filaments', 'optical', 'hybrid', 'membrane')
    for ($Index = 1; $Index -le 6; $Index++) {
        $ProfilePath = Join-Path $Evidence ("synth-$Index.json")
        $CapturePath = Join-Path $Evidence ("synth-$Index.png")
        $EngineLog = Join-Path $Evidence ("synth-$Index-engine.log")
        $Frames = $(if ($Index -eq 6) { 600 } else { 90 })
        $Clock = [System.Diagnostics.Stopwatch]::StartNew()
        Invoke-Checked -Name ("synth-$Index-packaged") -Executable $Application -Arguments (
            $Graphics + @('--log-file', $EngineLog, '--', "--patch-example=$Index", '--hide-panel',
                '--warmup=60', "--profile-frames=$Frames", "--profile=$ProfilePath", '--capture-frame=45', "--capture=$CapturePath")
        ) -TimeoutSeconds 480 -EngineLog $EngineLog
        $Profile = Get-Content -Raw $ProfilePath | ConvertFrom-Json
        $Dimensions = Read-PngDimensions -Path $CapturePath
        if ($Profile.build.source_sha -ne $SourceSha -or $Profile.preset -ne $PatchPresets[$Index - 1] -or
            -not $Profile.source_unchanged -or -not $Profile.synthesis.active -or $Profile.synthesis.fixed_ticks -lt 1 -or
            $Profile.synthesis.route_count -lt 1 -or $Profile.synthesis.samples -lt 1 -or $Profile.samples -lt $Frames -or
            $Profile.platform.headless -or $Profile.platform.driver -ne 'vulkan' -or -not $Profile.platform.software_device) {
            throw "Incomplete packaged synthesis profile: $Index"
        }
        $Qualification.synth_patches += [ordered]@{
            name = $PatchNames[$Index - 1]; preset = $Profile.preset; source_sha = $Profile.build.source_sha
            capture = (Split-Path -Leaf $CapturePath); capture_dimensions = $Dimensions
            capture_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $CapturePath).Hash.ToLowerInvariant()
            profile = (Split-Path -Leaf $ProfilePath); samples = $Profile.samples
            execution_wall_seconds = [Math]::Round($Clock.Elapsed.TotalSeconds, 3)
            wall_p50_ms = $Profile.wall_frame.p50_ms; wall_p95_ms = $Profile.wall_frame.p95_ms
            graph = $Profile.synthesis; device = $Profile.platform.device
        }
    }
    # A real input route test on the same source and pinned graphics stack.
    $GuiLog = Join-Path $Evidence 'gui-input-engine.log'
    $GuiPrefix = Join-Path $Evidence 'gui-input'
    Invoke-ExtractedScript -Name 'graphical-input' -ScriptName 'gui_input_probe.gd' -EngineArguments (
        $Graphics + @('--log-file', $GuiLog)
    ) -UserArguments @("--output-prefix=$GuiPrefix") -TimeoutSeconds 480 -EngineLog $GuiLog
    foreach ($Preset in @('nursery','garden','living','films','condensation','ecosystem')) {
        $ProfilePath = Join-Path $Evidence ($Preset + '.json')
        $CapturePath = Join-Path $Evidence ($Preset + '.png')
        $EngineLog = Join-Path $Evidence ($Preset + '-engine.log')
        Invoke-Checked -Name ($Preset + '-procedural-vulkan') -Executable $Application -Arguments (
            $Graphics + @('--log-file',$EngineLog,'--',"--preset=$Preset",'--hide-panel',
                '--warmup=45','--profile-frames=60',"--profile=$ProfilePath",
                '--capture-frame=30',"--capture=$CapturePath")
        ) -TimeoutSeconds 300 -EngineLog $EngineLog
        $Profile = Get-Content -Raw $ProfilePath | ConvertFrom-Json
        $Dimensions = Read-PngDimensions -Path $CapturePath
        if ($Profile.preset -ne $Preset -or $Profile.build.source_sha -ne $SourceSha -or
            -not $Profile.source_unchanged -or -not $Profile.matter.active -or -not $Profile.matter.visible -or
            $Profile.matter.regions.Count -ne 3 -or $Profile.draw_calls_3d -lt 1 -or $Profile.samples -lt 60 -or
            $Profile.platform.os -ne 'Windows' -or $Profile.platform.headless -or
            $Profile.platform.driver -ne 'vulkan' -or $Profile.platform.rendering_method -ne 'forward_plus' -or
            -not $Profile.platform.software_device -or
            $Profile.render_target_pixels[0] -ne $Dimensions[0] -or $Profile.render_target_pixels[1] -ne $Dimensions[1]) {
            throw "Incomplete procedural packaged execution: $Preset"
        }
        $Qualification.scenes += [ordered]@{
            preset=$Preset; status='EXECUTED'; capture=(Split-Path -Leaf $CapturePath)
            capture_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $CapturePath).Hash.ToLowerInvariant()
            capture_dimensions=$Dimensions; profile=(Split-Path -Leaf $ProfilePath)
            samples=$Profile.samples; device=$Profile.platform.device
            wall_p50_ms=$Profile.wall_frame.p50_ms; wall_p95_ms=$Profile.wall_frame.p95_ms
            draw_calls_3d=$Profile.draw_calls_3d; generated_regions=$Profile.matter.regions
        }
    }
    # Isolate the cost of the generated layer on the identical dense scene.
    $DisabledProfile = Join-Path $Evidence 'ecosystem-disabled.json'
    $DisabledLog = Join-Path $Evidence 'ecosystem-disabled-engine.log'
    Invoke-Checked -Name 'ecosystem-disabled' -Executable $Application -Arguments (
        $Graphics + @('--log-file',$DisabledLog,'--','--preset=ecosystem','--hide-panel','--no-matter',
            '--warmup=45','--profile-frames=60',"--profile=$DisabledProfile")
    ) -TimeoutSeconds 240 -EngineLog $DisabledLog
    $Disabled = Get-Content -Raw $DisabledProfile | ConvertFrom-Json
    if ($Disabled.matter.visible -or $Disabled.samples -lt 60 -or $Disabled.build.source_sha -ne $SourceSha) {
        throw 'Effect-disabled comparison did not suppress the procedural layer'
    }
    $Qualification.effect_disabled = 'ecosystem-disabled.json'
    # Additional views and effect-disabled comparison from the extracted executable.
    $Qualification.comparisons = @()
    foreach ($Preset in @('optical_dichroic','optical_weather','optical_lens','optical_garden','optical_microfibres','optical_ecosystem')) {
        $CapturePath = Join-Path $Evidence ($Preset + '-close.png')
        $ProfilePath = Join-Path $Evidence ($Preset + '-close.json')
        $EngineLog = Join-Path $Evidence ($Preset + '-close-engine.log')
        Invoke-Checked -Name ($Preset + '-close') -Executable $Application -Arguments (
            $Graphics + @('--log-file', $EngineLog, '--', "--preset=$Preset", '--hide-panel', '--close-optics',
                '--warmup=45', '--profile-frames=15', "--profile=$ProfilePath", '--capture-frame=30', "--capture=$CapturePath")
        ) -TimeoutSeconds 240 -EngineLog $EngineLog
        $Dimensions = Read-PngDimensions -Path $CapturePath
        $Qualification.comparisons += [ordered]@{preset=$Preset; mode='close'; capture=(Split-Path -Leaf $CapturePath);
            capture_sha256=(Get-FileHash -Algorithm SHA256 -LiteralPath $CapturePath).Hash.ToLowerInvariant(); dimensions=$Dimensions;
            profile=(Split-Path -Leaf $ProfilePath)}
    }
    foreach ($Preset in @('optical_weather','optical_lens','optical_garden','optical_ecosystem')) {
        $ProfilePath = Join-Path $Evidence ($Preset + '-legacy.json')
        $EngineLog = Join-Path $Evidence ($Preset + '-legacy-engine.log')
        Invoke-Checked -Name ($Preset + '-legacy') -Executable $Application -Arguments (
            $Graphics + @('--log-file', $EngineLog, '--', "--preset=$Preset", '--hide-panel', '--legacy-optics',
                '--warmup=60', '--profile-frames=60', "--profile=$ProfilePath")
        ) -TimeoutSeconds 240 -EngineLog $EngineLog
        $Disabled = Get-Content -Raw $ProfilePath | ConvertFrom-Json
        if ($Disabled.optical.optical_matter_mix -ne 0 -or $Disabled.optical.secondary_film_draws -ne 0 -or $Disabled.optical.refraction_screen_copy_active) {
            throw "Legacy comparison retained experimental optical passes: $Preset"
        }
        $Qualification.comparisons += [ordered]@{preset=$Preset; mode='legacy-optics'; profile=(Split-Path -Leaf $ProfilePath);
            wall_p50_ms=$Disabled.wall_frame.p50_ms; wall_p95_ms=$Disabled.wall_frame.p95_ms; draw_calls_3d=$Disabled.draw_calls_3d}
    }
    Invoke-ExtractedScript -Name 'ecology-graphical-input' -ScriptName 'gui_ecology_probe.gd' -EngineArguments (
        $Graphics + @('--log-file', (Join-Path $Evidence 'ecology-gui-engine.log'))
    ) -UserArguments @("--output-prefix=$(Join-Path $Evidence 'ecology-gui')") -EngineLog (Join-Path $Evidence 'ecology-gui-engine.log') -TimeoutSeconds 240
    $GuiReceipt = Get-Content -Raw (Join-Path $Evidence 'ecology-gui.json') | ConvertFrom-Json
    if ($GuiReceipt.status -ne 'PASS' -or $GuiReceipt.checks -lt 18) { throw 'Ecology graphical input receipt incomplete' }
    $Qualification.ecology_gui = $GuiReceipt
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
            -not $Profile.platform.software_device -or $Profile.digest -notmatch '^[0-9a-f]{64}$') {
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
    $Qualification.compositions = @()
    $Compositions = @('spectral_vortex', 'living_membrane', 'excitable_garden', 'condensation_instrument', 'light_terrarium', 'matter_orchestra')
    foreach ($Composition in $Compositions) {
        foreach ($View in @('overview', 'close')) {
            $Name = 'composition-' + $Composition + '-' + $View
            $ProfilePath = Join-Path $Evidence ($Name + '.json')
            $CapturePath = Join-Path $Evidence ($Name + '.png')
            $EngineLog = Join-Path $Evidence ($Name + '-engine.log')
            $Extra = @()
            if ($View -eq 'close') { $Extra += '--close-optics' }
            Invoke-Checked -Name $Name -Executable $Application -Arguments (
                $Graphics + @('--log-file', $EngineLog, '--', "--preset=composition.$Composition", '--hide-panel',
                    '--warmup=60', '--profile-frames=90', "--profile=$ProfilePath", '--capture-frame=45', "--capture=$CapturePath") + $Extra
            ) -TimeoutSeconds 480 -EngineLog $EngineLog
            $Profile = Get-Content -Raw $ProfilePath | ConvertFrom-Json
            $Dimensions = Read-PngDimensions -Path $CapturePath
            if ($Profile.build.source_sha -ne $SourceSha -or $Profile.build.tree_sha -ne $SourceTree -or
                $Profile.composition_id -ne "composition.$Composition" -or -not $Profile.source_unchanged -or
                -not $Profile.synthesis.active -or $Profile.synthesis.fixed_ticks -lt 1 -or
                $Profile.synthesis.missing_targets.Count -ne 0 -or -not $Profile.matter.active -or
                $Profile.samples -lt 90 -or $Profile.platform.headless -or
                $Profile.platform.driver -ne 'vulkan' -or $Profile.platform.rendering_method -ne 'forward_plus') {
                throw "Incomplete integrated composition execution: $Name"
            }
            $HasEcology = $Composition -in @('living_membrane', 'excitable_garden', 'light_terrarium', 'matter_orchestra')
            if ($HasEcology -and (-not $Profile.ecology.shared_bus -or $Profile.ecology.world_tick -lt 1 -or
                $Profile.spatial_ecology.organism_resources -lt 1 -or $Profile.ecology_digest -notmatch '^[0-9a-f]{64}$')) {
                throw "Integrated ecology representation did not execute: $Name"
            }
            $Qualification.compositions += [ordered]@{
                composition = $Profile.composition_id; view = $View; source_sha = $SourceSha; tree_sha = $SourceTree
                capture = (Split-Path -Leaf $CapturePath); capture_dimensions = $Dimensions
                capture_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $CapturePath).Hash.ToLowerInvariant()
                profile = (Split-Path -Leaf $ProfilePath); graph = $Profile.synthesis
                ecology = $Profile.ecology; spatial = $Profile.spatial_ecology
                startup_usec = $Profile.startup_usec; scene_prepare_usec = $Profile.scene_prepare_usec
                wall_p50_ms = $Profile.wall_frame.p50_ms; wall_p95_ms = $Profile.wall_frame.p95_ms
            }
        }
    }
    # Generated matter and spatial ecology share the explicit global mix-zero contract.
    $NoOpticsPath = Join-Path $Evidence 'composition-orchestra-legacy-optics.json'
    $NoOpticsLog = Join-Path $Evidence 'composition-orchestra-legacy-optics-engine.log'
    Invoke-Checked -Name 'composition-orchestra-legacy-optics' -Executable $Application -Arguments (
        $Graphics + @('--log-file', $NoOpticsLog, '--', '--preset=composition.matter_orchestra', '--hide-panel', '--legacy-optics',
            '--warmup=60', '--profile-frames=90', "--profile=$NoOpticsPath",
            '--capture-frame=45', "--capture=$(Join-Path $Evidence 'composition-orchestra-legacy-optics.png')")
    ) -TimeoutSeconds 480 -EngineLog $NoOpticsLog
    $NoOptics = Get-Content -Raw $NoOpticsPath | ConvertFrom-Json
    if ($NoOptics.optical.optical_matter_mix -ne 0 -or $NoOptics.optical.refraction_screen_copy_active -or
        $NoOptics.build.source_sha -ne $SourceSha -or $NoOptics.samples -lt 90) {
        throw 'Integrated effect-disabled optical comparison failed'
    }
    Invoke-ExtractedScript -Name 'graphical-capture-health' -ScriptName 'verify_captures.gd' -UserArguments @(
        "--capture-directory=$Evidence",
        "--output=$(Join-Path $Evidence 'capture-health.json')"
    ) -TimeoutSeconds 180
    $Qualification.capture_health = Get-Content -Raw (Join-Path $Evidence 'capture-health.json') | ConvertFrom-Json
    Write-TreeEvidence -Stage 'after-complete-qualification'
    # The release archive must still be the same bytes after qualification.
    Assert-FileHash -Path $Archive -Expected $PackageReceipt.sha256
    $Qualification.status = 'PASS'
    $Qualification.visual_evidence = 'All inherited feature scenes, six integrated compositions at overview/close, disabled-effect controls and actual extracted authoring; retain PNGs for human review'
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
