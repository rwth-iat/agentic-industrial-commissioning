[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent (
    Split-Path -Parent (
        Split-Path -Parent (
            Split-Path -Parent $PSScriptRoot
        )
    )
)
$adsRoot = Join-Path $repositoryRoot 'capabilities/twincat/ads'
$catalogPath = Join-Path $adsRoot 'catalog.psd1'
$recipeRoot = Join-Path $adsRoot 'recipes'
$readOnlyRoot = Join-Path $recipeRoot 'read-only'
$stateChangingRoot = Join-Path $recipeRoot 'state-changing'
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure {
    param([string]$Message)
    $failures.Add($Message)
}

$recipes = @(Get-ChildItem -LiteralPath $recipeRoot -Recurse -File -Filter '*.ps1')
if ($recipes.Count -lt 1) {
    Add-Failure 'No ADS recipes were found.'
}

foreach ($recipe in $recipes) {
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $recipe.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        Add-Failure "$($recipe.Name) has $($parseErrors.Count) parse error(s)."
        continue
    }

    $content = Get-Content -LiteralPath $recipe.FullName -Raw
    $parameterNames = @($ast.ParamBlock.Parameters.Name.VariablePath.UserPath)
    foreach ($requiredName in @('NetId', 'AdsDll')) {
        if ($requiredName -notin $parameterNames) {
            Add-Failure "$($recipe.Name) is missing parameter $requiredName."
            continue
        }
        $parameterAst = $ast.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq $requiredName }
        if ($null -ne $parameterAst.DefaultValue) {
            Add-Failure "$($recipe.Name) gives environment-specific parameter $requiredName a default."
        }
        if ($parameterAst.Extent.Text -notmatch '\[Parameter\(Mandatory\)\]') {
            Add-Failure "$($recipe.Name) does not make environment-specific parameter $requiredName mandatory."
        }
    }

    if ($content -match '(?<!\d)(?:\d{1,3}\.){5}\d{1,3}(?!\d)') {
        Add-Failure "$($recipe.Name) contains a concrete-looking AMS NetId."
    }
    if ($content -match '(?i)GVL_|F16|Y17|N13|H6A-') {
        Add-Failure "$($recipe.Name) contains a test-system-specific identifier."
    }

    $commandNames = @(
        $ast.FindAll(
            { param($node) $node -is [System.Management.Automation.Language.CommandAst] },
            $true
        ) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ }
    )

    if ($recipe.DirectoryName -eq $readOnlyRoot) {
        if ($content -notmatch '# SAFETY: READ_ONLY') {
            Add-Failure "$($recipe.Name) is missing the READ_ONLY marker."
        }
        if ($content -match '(?i)WriteControl|WriteSymbol|WriteAny|CreateVariableHandle') {
            Add-Failure "$($recipe.Name) contains a potentially state-changing ADS API."
        }
    }
    elseif ($recipe.DirectoryName -eq $stateChangingRoot) {
        if ($content -notmatch '# SAFETY: STATE_CHANGING') {
            Add-Failure "$($recipe.Name) is missing the STATE_CHANGING marker."
        }
        if ('HumanApproved' -notin $parameterNames) {
            Add-Failure "$($recipe.Name) is missing the HumanApproved guard parameter."
        }
        if ($content -notmatch 'if \(-not \$HumanApproved\)') {
            Add-Failure "$($recipe.Name) does not enforce the HumanApproved guard."
        }
        if ($recipe.Name -like 'system-*.ps1') {
            if ('Start-Sleep' -notin $commandNames -or $content -notmatch '\$after\s*=\s*\$check\.ReadState') {
                Add-Failure "$($recipe.Name) does not perform an explicit system-state readback."
            }
        }
        elseif ($content -match '(?i)WriteSymbol') {
            if ($content -notmatch '(?i)ReadSymbol' -or $content -notmatch '(?i)Verified\s*=\s*\$true') {
                Add-Failure "$($recipe.Name) does not perform an explicit symbol readback."
            }
        }
        if ($recipe.Name -eq 'system-run-to-config.ps1' -and $content -notmatch 'VERIFICATION: EXPERIMENTAL') {
            Add-Failure "$($recipe.Name) must remain marked experimental until final readback is preserved."
        }
    }
    else {
        Add-Failure "$($recipe.Name) is outside a recognized safety directory."
    }
}

$configTemplate = Get-Content -LiteralPath (Join-Path $adsRoot 'config.example.psd1') -Raw
foreach ($placeholder in @('<AMS-NET-ID>', '<PATH-TO-TWINCAT.ADS.DLL>')) {
    if ($configTemplate -notmatch [regex]::Escape($placeholder)) {
        Add-Failure "Config template is missing placeholder $placeholder."
    }
}

$catalog = Import-PowerShellDataFile -LiteralPath $catalogPath
if ($catalog.SchemaVersion -ne 1) {
    Add-Failure "Unexpected ADS capability catalog schema: $($catalog.SchemaVersion)."
}
if ($catalog.Capabilities.Count -ne $recipes.Count) {
    Add-Failure "Catalog contains $($catalog.Capabilities.Count) entries for $($recipes.Count) recipes."
}
foreach ($entry in $catalog.Capabilities.GetEnumerator()) {
    $catalogRecipe = Join-Path $adsRoot $entry.Value.Recipe
    if (-not (Test-Path -LiteralPath $catalogRecipe -PathType Leaf)) {
        Add-Failure "Catalog entry $($entry.Key) references a missing recipe."
        continue
    }
    $recipeContent = Get-Content -LiteralPath $catalogRecipe -Raw
    $recipeTokens = $null
    $recipeParseErrors = $null
    $recipeAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $catalogRecipe,
        [ref]$recipeTokens,
        [ref]$recipeParseErrors
    )
    $recipeParameterNames = @($recipeAst.ParamBlock.Parameters.Name.VariablePath.UserPath)
    foreach ($userParameter in @($entry.Value.UserParameters)) {
        if ($userParameter -notin $recipeParameterNames) {
            Add-Failure "Catalog entry $($entry.Key) declares unknown recipe parameter $userParameter."
        }
    }
    if ($entry.Value.Safety -eq 'READ_ONLY' -and $recipeContent -notmatch '# SAFETY: READ_ONLY') {
        Add-Failure "Catalog safety for $($entry.Key) disagrees with its recipe."
    }
    if ($entry.Value.Safety -eq 'STATE_CHANGING' -and $recipeContent -notmatch '# SAFETY: STATE_CHANGING') {
        Add-Failure "Catalog safety for $($entry.Key) disagrees with its recipe."
    }
}

$remoteScripts = @(
    Join-Path $repositoryRoot 'scripts/remote/Start-AgentRemoteBridge.ps1'
    Join-Path $repositoryRoot 'scripts/remote/Invoke-AgentRemote.ps1'
)
foreach ($remoteScript in $remoteScripts) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $remoteScript,
        [ref]$tokens,
        [ref]$parseErrors
    )
    if ($parseErrors.Count -gt 0) {
        Add-Failure "$(Split-Path -Leaf $remoteScript) has $($parseErrors.Count) parse error(s)."
    }
}

$bridgeSource = Get-Content -LiteralPath $remoteScripts[0] -Raw
$clientSource = Get-Content -LiteralPath $remoteScripts[1] -Raw
if ($bridgeSource -notmatch '\[System\.Net\.IPAddress\]::Loopback') {
    Add-Failure 'Start-AgentRemoteBridge.ps1 does not bind explicitly to loopback.'
}
if ($bridgeSource -notmatch 'RandomNumberGenerator' -or $bridgeSource -notmatch 'sessionToken') {
    Add-Failure 'Start-AgentRemoteBridge.ps1 does not create a per-session token.'
}
if ($bridgeSource -match '\[string\]\$ComputerName\s*=') {
    Add-Failure 'Start-AgentRemoteBridge.ps1 contains a default remote host.'
}
if ($bridgeSource -notmatch '\[switch\]\$ShowEndpointDetails') {
    Add-Failure 'Start-AgentRemoteBridge.ps1 does not make endpoint output opt-in.'
}
if ($bridgeSource -notmatch 'Import-PowerShellDataFile' -or $bridgeSource -notmatch '\$ConfigPath') {
    Add-Failure 'Start-AgentRemoteBridge.ps1 does not support an ignored local configuration file.'
}
if ($clientSource -notmatch "state\.host -ne '127\.0\.0\.1'") {
    Add-Failure 'Invoke-AgentRemote.ps1 does not reject non-loopback state endpoints.'
}
if ($clientSource -notmatch '\[hashtable\]\$Arguments' -or $clientSource -notmatch 'arguments = \$Arguments') {
    Add-Failure 'Invoke-AgentRemote.ps1 does not transmit named recipe arguments separately.'
}

$remoteConfigTemplate = Get-Content -LiteralPath (
    Join-Path $repositoryRoot 'scripts/remote/config.example.psd1'
) -Raw
if ($remoteConfigTemplate -notmatch [regex]::Escape('<ENGINEERING-HOST>')) {
    Add-Failure 'Remote config template is missing its host placeholder.'
}

$selectorPath = Join-Path $repositoryRoot 'scripts/capabilities/twincat/Invoke-AdsCapability.ps1'
$selectorTokens = $null
$selectorErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $selectorPath,
    [ref]$selectorTokens,
    [ref]$selectorErrors
)
if ($selectorErrors.Count -gt 0) {
    Add-Failure "Invoke-AdsCapability.ps1 has $($selectorErrors.Count) parse error(s)."
}
$selectorSource = Get-Content -LiteralPath $selectorPath -Raw
if ($selectorSource -notmatch "Safety -ne 'READ_ONLY'") {
    Add-Failure 'ADS capability selector does not explicitly reject state-changing entries.'
}
if ($selectorSource -notmatch "'WaitSymbolCondition'") {
    Add-Failure 'ADS capability selector does not bind WaitSymbolCondition parameters.'
}

$listedCapabilities = @(& $selectorPath -List)
$expectedReadOnlyCount = @(
    $catalog.Capabilities.GetEnumerator() |
        Where-Object { $_.Value.Safety -eq 'READ_ONLY' }
).Count
if ($listedCapabilities.Count -ne $expectedReadOnlyCount) {
    Add-Failure "Selector listed $($listedCapabilities.Count) entries; expected $expectedReadOnlyCount read-only entries."
}

$stateChangeBlocked = $false
try {
    & $selectorPath -Capability 'SystemConfigToRun' 2>&1 | Out-Null
}
catch {
    $stateChangeBlocked = $_.Exception.Message -match 'intentionally blocked'
}
if (-not $stateChangeBlocked) {
    Add-Failure 'ADS capability selector did not reject a state-changing catalog entry.'
}

$controlledSelectorPath = Join-Path $repositoryRoot 'scripts/capabilities/twincat/Invoke-AdsControlledAction.ps1'
$controlledTokens = $null
$controlledErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $controlledSelectorPath,
    [ref]$controlledTokens,
    [ref]$controlledErrors
)
if ($controlledErrors.Count -gt 0) {
    Add-Failure "Invoke-AdsControlledAction.ps1 has $($controlledErrors.Count) parse error(s)."
}
$controlledSource = Get-Content -LiteralPath $controlledSelectorPath -Raw
foreach ($requiredPattern in @(
    "Safety -eq 'STATE_CHANGING'",
    'RequiredApproval',
    'if \(-not \$Execute\)',
    '\$arguments\.HumanApproved\s*=\s*\$true'
)) {
    if ($controlledSource -notmatch $requiredPattern) {
        Add-Failure "Controlled ADS selector is missing required pattern: $requiredPattern"
    }
}

$listedControlledCapabilities = @(& $controlledSelectorPath -List)
$expectedControlledCount = @(
    $catalog.Capabilities.GetEnumerator() |
        Where-Object { $_.Value.Safety -eq 'STATE_CHANGING' }
).Count
if ($listedControlledCapabilities.Count -ne $expectedControlledCount) {
    Add-Failure "Controlled selector listed $($listedControlledCapabilities.Count) entries; expected $expectedControlledCount state-changing entries."
}

$preparedPlan = & $controlledSelectorPath -Capability SystemConfigToRun
if ($preparedPlan.Capability -ne 'SystemConfigToRun' -or
    $preparedPlan.RequiredApproval -notmatch '^APPROVE SystemConfigToRun [A-F0-9]{12}$') {
    Add-Failure 'Controlled selector did not prepare a deterministic Config-to-Run approval plan.'
}

$numericPlan = & $controlledSelectorPath `
    -Capability WriteSymbolGuarded `
    -Symbol 'GVL_Demo.Setpoint' `
    -Type Single `
    -ExpectedValue '0' `
    -Value '30' `
    -MinimumValue '0' `
    -MaximumValue '100' `
    -ExpectedAdsState Run
if ($numericPlan.Operation.minimum_value -ne '0' -or $numericPlan.Operation.maximum_value -ne '100') {
    Add-Failure 'Controlled selector did not include numeric write bounds in the prepared operation.'
}

$outOfRangeBlocked = $false
try {
    & $controlledSelectorPath `
        -Capability WriteSymbolGuarded `
        -Symbol 'GVL_Demo.Setpoint' `
        -Type Single `
        -ExpectedValue '0' `
        -Value '101' `
        -MinimumValue '0' `
        -MaximumValue '100' `
        -ExpectedAdsState Run 2>&1 | Out-Null
}
catch {
    $outOfRangeBlocked = $_.Exception.Message -match 'outside the declared write range'
}
if (-not $outOfRangeBlocked) {
    Add-Failure 'Controlled selector did not reject an out-of-range numeric write during preparation.'
}

$executionBlocked = $false
try {
    & $controlledSelectorPath -Capability SystemConfigToRun -Execute -Approval 'not-approved' 2>&1 | Out-Null
}
catch {
    $executionBlocked = $_.Exception.Message -match 'Execution blocked'
}
if (-not $executionBlocked) {
    Add-Failure 'Controlled selector did not block execution without the exact prepared approval phrase.'
}

$readOnlyBlockedByControlledSelector = $false
try {
    & $controlledSelectorPath -Capability ReadSystemState 2>&1 | Out-Null
}
catch {
    $readOnlyBlockedByControlledSelector = $_.Exception.Message -match 'read-only selector'
}
if (-not $readOnlyBlockedByControlledSelector) {
    Add-Failure 'Controlled selector did not reject a read-only catalog entry.'
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Output "FAIL $_" }
    exit 1
}

Write-Output "All $($recipes.Count) ADS recipes, the catalog, selector, and both remote bridge scripts passed offline checks."
exit 0
