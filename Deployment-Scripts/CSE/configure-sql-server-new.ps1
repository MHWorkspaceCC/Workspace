 param(
	[string]$installersStgAcctKey,
	[string]$saUsername = "wsadmin",
	[string]$saPassword = "Workspace!DB!2017",
	[string]$loginUsername = "wsapp",
	[string]$loginPassword = "Workspace!DB!2017",
	[string]$storageAccountName = "stginstallerswspdpr",
	[string]$containerName = "sqlserver",
	[string]$sqlInstallBlobName = "en_sql_server_2016_enterprise_with_service_pack_1_x64_dvd_9542382.iso",
	[string]$ssmsInstallBlobName = "SSMS-Setup-ENU.exe",
	[string]$destinationSqlIso = "d:\sqlserver.iso",
	[string]$destinationSSMS = "d:\SSMS-Setup-ENU.exe",
	[string]$databaseName = "AdventureWorks",
	[string]$databaseMdfFile = "e:\AdventureWorks2012_Data.mdf" 
)

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\configure.log" -Value $logstring
	Write-Host $logstring
} 

Try
{
<#
	Write-Log("In configure sql server")
	Write-Log("Installers key: " + $installersStgAcctKey)
	Write-Log("saUsername: " + $saUsername)
	Write-Log("saPassword: " + $saPassword)
	Write-Log("loginUsername: " + $loginUsername)
	Write-Log("loginPassword: " + $loginPassword)

	Write-Log("Trusting PSGallery")
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
	Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
	Write-Log("Installing AzureRM, xSqlServer, and SqlServer")
	Install-Module -Name AzureRM -Repository PSGallery
	Install-Module -Name xSqlServer -Repository PSGallery
	Install-Module -Name SqlServer -Repository PSGallery

	Import-Module SqlServer

	Write-Log("Starting configuration")

	$storageAccountKey = $installersStgAcctKey
	$ssmsInstallBlobName = "SSMS-Setup-ENU.exe"
	$destinationSqlIso = "d:\sqlserver.iso"
	$destinationSSMS = "d:\SSMS-Setup-ENU.exe"

	$storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
	Get-AzureStorageBlobContent -Blob $sqlInstallBlobName -Container $containerName -Destination $destinationSqlIso -Context $storageContext
	Get-AzureStorageBlobContent -Blob $ssmsInstallBlobName -Container $containerName -Destination $destinationSSMS -Context $storageContext
	Mount-DiskImage -ImagePath d:\sqlserver.iso 
	$sqlInstallDrive = (Get-DiskImage -ImagePath "d:\sqlserver.iso" | Get-Volume).DriveLetter

	Write-Log("Mounted sql server media on " + $sqlInstallDrive)
#>	
    $loginPwdSecure = ConvertTo-SecureString $loginPassword -AsPlainText -Force
    $loginCred = New-Object System.Management.Automation.PSCredential ($loginUsername, $loginPwdSecure)

    $sysAcctPasswordSecure = $saPassword | ConvertTo-SecureString -AsPlainText -Force
    $sysAcctCreds = New-Object -TypeName pscredential -ArgumentList $saUsername, $saPasswordSecure

    $saPwd = $sysAcctPasswordSecure
    $saCred = New-Object -TypeName pscredential -ArgumentList "sa", $saPwd
    <#
	Write-Log("Starting SQL Server Install")
	. ./SqlStandaloneDSC

	$dataDisk = (Get-Volume -FileSystemLabel WorkspaceDB).DriveLetter
	Write-Log("The data disk drive letter is " + $dataDisk)

	SqlStandaloneDSC -ConfigurationData SQLConfigurationData.psd1 -LoginCredential $loginCred -SysAdminAccount $saCreds -saCredential $sysAcctCreds -installDisk $sqlInstallDrive
	Start-DscConfiguration .\SqlStandaloneDSC -Verbose -wait -Force

	Write-Log("Installed SQL Server")

	Write-Log("Installing SSMS")
	Start-Process $destinationSSMS "/install /quiet /norestart /log d:\ssms-log.txt" -Wait
	Write-Log("Installed SSMS")

	Write-Log("Cleaning up")
	Dismount-DiskImage -ImagePath d:\sqlserver.iso
	Write-Log("Cleaned up")
	Remove-Item -Path $destinationSqlIso
	Remove-Item -Path $destinationSSMS
    Remove-Item -Path d:\log*.txt
    Remove-Item -Path d:\ssms-*.txt
    #>
    Write-Log("Attaching database")
    $ss = New-Object "Microsoft.SqlServer.Management.Smo.Server" "localhost"
    $ss.ConnectionContext.LoginSecure = $false
    $ss.ConnectionContext.Login = "sa"
    $ss.ConnectionContext.Password = $saPassword
    Write-Log $ss.Information.Version

	$mdfs = $ss.EnumDetachedDatabaseFiles($databaseMdfFile)
	$ldfs = $ss.EnumDetachedLogFiles($databaseMdfFile)

	$files = New-Object System.Collections.Specialized.StringCollection
    Write-Log("Enumerating mdfs")
	ForEach-Object -InputObject $mdfs {
        Write-Log($_)
		$files.Add($_)
	}
    Write-Log "Enumerating ldfs"
	ForEach-Object -InputObject $ldfs {
        Write-Log($_)
		$files.Add($_)
	}
	$ss.AttachDatabase($databaseName, $files)
	Write-Log("Attached database")

	Write-Log("Checking database info")
	$db = $ss.Databases[$databaseName]
	Write-Log("The database is:")
    Write-Log($db)
	Write-Log("Database users:")
    Write-log($db.Users)

	Write-Log("Getting the login for : " + $loginUsername)
    $wsAppLogin = $ss.Logins[$loginUsername]
    Write-Log("Database login is: " + $wsAppLogin)

	Try
	{
		Write-Log("Creating a login for: " + $loginUsername)
		$dbuser = New-Object "Microsoft.SqlServer.Management.Smo.User" $db, $loginUsername
		$dbuser.Login = $loginUsername
		Write-Log("Calling create")
		$dbuser.Create()
		Write-Log("Created, adding user to roles")

		$db.Roles["db_datareader"].AddMember($dbuser.Name)
		$db.Roles["db_datawriter"].AddMember($dbuser.Name)
	}
	Catch
	{
		Write-Log("DB Exception")
		Write-Log($_.Exception.Message)
		Write-Log($_.Exception.InnerException)
	}

	Write-Log("All done!")
}
Catch
{
	Write-Log("Exception")
	Write-Log($_.Exception.Message)
	Write-Log($_.Exception.InnerException)
} 
