  param(
	[string]$installersStgAcctKey = "KRihdvk4dDFQkOloPqpk0P5DtnpNOr13Hh9TfBywjyjcE7wSgLSgNud8JnEzTZI4ZAbKnytoFiLfI0kJZ4z4gQ==",
	[string]$saUserName = "wsadmin",
	[string]$saPassword = "Workspace!DB!2017",
	[string]$loginUserName = "wsapp",
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
	Write-Log("In configure sql server")
	Write-Log("Installers key: " + $installersStgAcctKey)
	Write-Log("saUsername: " + $saUsername)
	Write-Log("saPassword: " + $saPassword)
	Write-Log("loginUsername: " + $loginUsername)
	Write-Log("loginPassword: " + $loginPassword)
	Write-Log("storageAccountName: " + $storageAccountName)
	Write-Log("sqlInstallBlobName: " + $sqlInstallBlobName)
	Write-Log("containerName: " + $containerName)
	Write-Log("ssmsInstallBlobName: " + $ssmsInstallBlobName)
	Write-Log("destinationSqlIso: " + $destinationSqlIso)
	Write-Log("destinationSSMS: " + $destinationSSMS)
	Write-Log("databaseName: " + $databaseName)
	Write-Log("databaseMdfFile: " + $databaseMdfFile)

	Write-Log("Trusting PSGallery")
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
	Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
	Write-Log("Installing AzureRM, xSqlServer, and SqlServer")
	Install-Module -Name AzureRM -Repository PSGallery
	Install-Module -Name xSqlServer -Repository PSGallery
	Install-Module -Name SqlServer -Repository PSGallery

	Import-Module SqlServer

	Write-Log("Starting configuration")

	$ssmsInstallBlobName = "SSMS-Setup-ENU.exe"
	$destinationSqlIso = "d:\sqlserver.iso"
	$destinationSSMS = "d:\SSMS-Setup-ENU.exe"

	$storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $installersStgAcctKey
	Get-AzureStorageBlobContent -Blob $sqlInstallBlobName -Container $containerName -Destination $destinationSqlIso -Context $storageContext
	Get-AzureStorageBlobContent -Blob $ssmsInstallBlobName -Container $containerName -Destination $destinationSSMS -Context $storageContext
	Mount-DiskImage -ImagePath d:\sqlserver.iso 
	$sqlInstallDrive = (Get-DiskImage -ImagePath "d:\sqlserver.iso" | Get-Volume).DriveLetter

	Write-Log("Mounted sql server media on " + $sqlInstallDrive)
		
    Write-Log("Creating credentials for app login")
    $loginPwdSecure = ConvertTo-SecureString $loginPassword -AsPlainText -Force
    $loginCred = New-Object System.Management.Automation.PSCredential ($loginUserName, $loginPwdSecure)

    Write-Log("Creating credentials for sys account")
    $sysAcctPasswordSecure = $saPassword | ConvertTo-SecureString -AsPlainText -Force
    $sysAcctCreds = New-Object -TypeName pscredential -ArgumentList $saUserName, $sysAcctPasswordSecure

    Write-Log("Creating credentials for sa")
    $saCred = New-Object -TypeName pscredential -ArgumentList "sa", $sysAcctPasswordSecure
    
	$dataDisk = (Get-Volume -FileSystemLabel WorkspaceDB).DriveLetter
	Write-Log("The data disk drive letter is " + $dataDisk)

	Write-Log("Sourcing SqlStandaloneDSC")
	. ./SqlStandaloneDSC
	
	Write-Log("Configuring SQLServer DSC")
	SqlStandaloneDSC -ConfigurationData SQLConfigurationData.psd1 -LoginCredential $loginCred -SysAdminAccount $saCreds -saCredential $sysAcctCreds -installDisk $sqlInstallDrive
	Write-Log("Starting SQL Server Install")
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
    
    Write-Log("Attaching database")
    $ss = New-Object "Microsoft.SqlServer.Management.Smo.Server" "localhost"
    $ss.ConnectionContext.LoginSecure = $false
    $ss.ConnectionContext.Login = "sa"
    $ss.ConnectionContext.Password = $saPassword
    Write-Log($ss.Information.Version)

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

	Write-Log("Configuring database login")

	if ($ss.Logins.Contains($loginUsername))
	{
		Write-Host "Login exists, dropping"
		$ss.Logins[$loginUsername].Drop()
	}

	Write-Log("Creating login")
	$login = New-Object "Microsoft.SqlServer.Management.Smo.Login" $ss, $loginUsername
	$login.LoginType = [Microsoft.SqlServer.Management.Smo.LoginType]::SqlLogin
	$login.PasswordExpirationEnabled = $false
	$securePwd = ConvertTo-SecureString $loginPassword -AsPlainText -Force
	$login.Create($securePwd)

	Write-Host("Configuring database user")
	if ($db.Users.Contains($loginUserName))
	{
		Write-Host "User exists, dropping"
		$db.Users[$loginUserName].Drop()
	}

	Write-Log("Creating user")
	$dbuser = New-Object "Microsoft.SqlServer.Management.Smo.User" $db, $loginUserName
	$dbuser.Login = $loginUserName
	$dbuser.Create()

	$db.Roles['db_datareader'].AddMember($dbuser.Name)
	$db.Roles['db_datawriter'].AddMember($dbuser.Name)

	Write-Log("All done!")
}
Catch
{
	Write-Log("Exception")
	Write-Log($_.Exception.Message)
	Write-Log($_.Exception.InnerException)
} 
 
