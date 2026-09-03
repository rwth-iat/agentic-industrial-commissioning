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
            Verification     = 'prepared'
            UserParameters   = @('Symbol', 'Type')
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
    }
}
