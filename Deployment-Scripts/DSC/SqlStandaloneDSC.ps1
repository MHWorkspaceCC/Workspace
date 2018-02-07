#
# SqlStandalone.ps1
#
<#
    .EXAMPLE
        This example shows how to install a default instance of SQL Server on a single server.
    .NOTES
        SQL Server setup is run using the SYSTEM account. Even if SetupCredential is provided
        it is not used to install SQL Server at this time (see issue #139).
#>
Configuration SQLStandaloneDSC
{
    [CmdletBinding()]
    param
    (
        [pscredential]$SysAdminAccount,
        [pscredential]$LoginCredential,
        [pscredential]$saCredential,
		[string]$installDisk
    )

    Import-DscResource -ModuleName xSQLServer

    node localhost
    {
        #region Install prerequisites for SQL Server
        WindowsFeature 'NetFramework35'
        {
            Name   = 'NET-Framework-Core'
            Ensure = 'Present'
        }

        WindowsFeature 'NetFramework45'
        {
            Name   = 'NET-Framework-45-Core'
            Ensure = 'Present'
        }
        #endregion Install prerequisites for SQL Server

        #region Install SQL Server
        xSQLServerSetup 'InstallDefaultInstance'
        {
            InstanceName         = 'MSSQLSERVER'
            Features             = 'SQLENGINE,AS'
            SQLSysAdminAccounts  = "wsadmin"
            ASSysAdminAccounts   = "wsadmin"
            SourcePath           = $installDisk + ":\"
            SecurityMode         = "SQL"
            SAPWD                = $saCredential

            DependsOn            = '[WindowsFeature]NetFramework35', '[WindowsFeature]NetFramework45'
        }

		xSqlServerFirewall 'InstallDefaultInstance'
		{
			Ensure               = 'Present'
            SourcePath           = $installDisk + ":\"
			DependsOn            = @("[xSqlServerSetup]InstallDefaultInstance")         
			Features             = "SQLENGINE" 
            InstanceName         = 'MSSQLSERVER'
		}

        xSQLServerLogin 'InstallDefaultInstance'
        {
            Ensure = 'Present'
            Name = 'wsapp'
            LoginType = 'SqlLogin'
            SqlServer = "localhost"
            SqlInstanceName = "MSSQLSERVER"
            LoginCredential = $LoginCredential
            LoginMustChangePassword = $false
            LoginPasswordExpirationEnabled = $false
            LoginPasswordPolicyEnforced = $false
            PsDscRunAsCredential = $SysAdminAccount
        }
		
		#endregion Install SQL Server
    }
}
