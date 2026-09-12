@{
    SchemaVersion = 1

    Capabilities = @{
        ReadSystemState = @{
            Order            = 10
            Label            = 'TwinCAT system state'
            Description      = 'Read the TwinCAT system-service state.'
            Recipe           = 'recipes/read-only/read-system-state.ps1'
            PortConfigKey    = 'SystemPort'
            Safety           = 'READ_ONLY'
            Verification     = 'verified'
            UserParameters   = @()
        }

        ReadPlcState = @{
            Order            = 20
            Label            = 'PLC runtime state'
            Description      = 'Read the configured PLC runtime state.'
            Recipe           = 'recipes/read-only/read-plc-state.ps1'
            PortConfigKey    = 'PlcPort'
            Safety           = 'READ_ONLY'
            Verification     = 'verified'
            UserParameters   = @()
        }

        ListSymbols = @{
            Order            = 30
            Label            = 'List PLC symbols'
            Description      = 'Load the PLC symbol table and return its first entries.'
            Recipe           = 'recipes/read-only/list-symbols.ps1'
            PortConfigKey    = 'PlcPort'
            Safety           = 'READ_ONLY'
            Verification     = 'verified'
            UserParameters   = @('First')
        }

        SearchSymbols = @{
            Order            = 40
            Label            = 'Search PLC symbols'
            Description      = 'Search PLC symbol names with a regular expression.'
            Recipe           = 'recipes/read-only/search-symbols.ps1'
            PortConfigKey    = 'PlcPort'
            Safety           = 'READ_ONLY'
            Verification     = 'verified'
            UserParameters   = @('Pattern')
        }

        ReadSymbol = @{
            Order            = 50
            Label            = 'Read primitive PLC symbol'
            Description      = 'Read one primitive symbol after its datatype has been verified.'
            Recipe           = 'recipes/read-only/read-symbol.ps1'
            PortConfigKey    = 'PlcPort'
            Safety           = 'READ_ONLY'
            Verification     = 'verified'
            UserParameters   = @('Symbol', 'Type')
        }

        WaitSymbolCondition = @{
            Order            = 60
            Label            = 'Wait for primitive PLC symbol value'
            Description      = 'Poll one primitive symbol until it reaches an expected value or times out.'
            Recipe           = 'recipes/read-only/wait-symbol-condition.ps1'
            PortConfigKey    = 'PlcPort'
            Safety           = 'READ_ONLY'
            Verification     = 'verified'
            UserParameters   = @('Symbol', 'Type', 'ExpectedValue', 'TimeoutSeconds', 'PollIntervalMilliseconds', 'NumericTolerance')
        }

        ObserveSymbolDuration = @{
            Order            = 65
            Label            = 'Observe primitive PLC symbol duration'
            Description      = 'Verify that a primitive PLC symbol continuously remains at an expected value for a bounded duration.'
            Recipe           = 'recipes/read-only/observe-symbol-duration.ps1'
            PortConfigKey    = 'PlcPort'
            Safety           = 'READ_ONLY'
            Verification     = 'experimental'
            UserParameters   = @('Symbol', 'Type', 'ExpectedValue', 'DurationSeconds', 'PollIntervalMilliseconds', 'NumericTolerance')
        }

        ReadBindingPreflight = @{
            Order            = 70
            Label            = 'Commissioning binding preflight'
            Description      = 'Read PLC state and a bounded set of resolved runtime bindings without writes.'
            Recipe           = 'recipes/read-only/read-binding-preflight.ps1'
            PortConfigKey    = 'PlcPort'
            Safety           = 'READ_ONLY'
            Verification     = 'experimental'
            UserParameters   = @('Bindings', 'ExpectedAdsState')
        }

        SystemConfigToRun = @{
            Order            = 110
            Label            = 'Request Config to Run'
            Description      = 'Request a TwinCAT system transition from Config to Run.'
            Recipe           = 'recipes/state-changing/system-config-to-run.ps1'
            PortConfigKey    = 'SystemPort'
            Safety           = 'STATE_CHANGING'
            Verification     = 'verified'
            UserParameters   = @('HumanApproved', 'WaitSeconds')
        }

        SystemRunToConfig = @{
            Order            = 120
            Label            = 'Request Run to Config'
            Description      = 'Request a TwinCAT system transition from Run to Config.'
            Recipe           = 'recipes/state-changing/system-run-to-config.ps1'
            PortConfigKey    = 'SystemPort'
            Safety           = 'STATE_CHANGING'
            Verification     = 'experimental'
            UserParameters   = @('HumanApproved', 'WaitSeconds')
        }

        WriteSymbolGuarded = @{
            Order            = 210
            Label            = 'Guarded primitive symbol write'
            Description      = 'Compare, write once, and verify one primitive PLC symbol.'
            Recipe           = 'recipes/state-changing/write-symbol-guarded.ps1'
            PortConfigKey    = 'PlcPort'
            Safety           = 'STATE_CHANGING'
            Verification     = 'experimental'
            UserParameters   = @('HumanApproved', 'Symbol', 'Type', 'ExpectedValue', 'Value', 'ExpectedAdsState', 'MinimumValue', 'MaximumValue', 'ReadbackTimeoutSeconds', 'PollIntervalMilliseconds', 'NumericTolerance')
        }

        PulseBooleanRequest = @{
            Order            = 220
            Label            = 'Pulse Boolean request and verify acknowledgement'
            Description      = 'Pulse one Boolean PLC request and wait for a separate primitive acknowledgement.'
            Recipe           = 'recipes/state-changing/pulse-boolean-request.ps1'
            PortConfigKey    = 'PlcPort'
            Safety           = 'STATE_CHANGING'
            Verification     = 'verified'
            UserParameters   = @('HumanApproved', 'RequestSymbol', 'AcknowledgementSymbol', 'AcknowledgementType', 'ExpectedInitialAcknowledgement', 'ExpectedFinalAcknowledgement', 'ExpectedAdsState', 'PulseMilliseconds', 'AcknowledgementTimeoutSeconds', 'PollIntervalMilliseconds', 'NumericTolerance')
        }

    }
}
