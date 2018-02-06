#
# ConfigurationData.psd1
#
@{
    AllNodes = @(
        @{
            NodeName = '*'
            PSDscAllowPlainTextPassword = $true
        },
        @{
            NodeName = 'localhost'
        }
    )
}