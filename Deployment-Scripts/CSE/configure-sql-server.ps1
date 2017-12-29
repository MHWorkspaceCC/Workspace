param(
	[string]$installersStgAcctKey,
	[string]$saUsername,
	[string]$saPassword
)

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\configure.log" -Value $logstring
	Write-Host $logstring
} 

Try
{
	Write-Log "In configure sql server"
	Write-Log "Installers key: " $installersStgAcctKey
	Write-Log "saUsername: " $saUsername
	Write-Log "saPassword: " $saPassword

	Write-Log "Trusting PSGallery"
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
	Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
	Write-Log "Installing AzureRM, xSqlServer, and SqlServer"
	Install-Module -Name AzureRM -Repository PSGallery
	Install-Module -Name xSqlServer -Repository PSGallery
	Install-Module -Name SqlServer -Repository PSGallery

	Import-Module SqlServer

	Write-Log "Starting configuration"

	$storageAccountKey = $installersStgAcctKey
	$storageAccountName = "stginstallerswspdpr"
	$containerName = "sqlserver"
	$sqlInstallBlobName = "en_sql_server_2016_enterprise_with_service_pack_1_x64_dvd_9542382.iso"
	$ssmsInstallBlobName = "SSMS-Setup-ENU.exe"
	$destinationSqlIso = "d:\sqlserver.iso"
	$destinationSSMS = "d:\SSMS-Setup-ENU.exe"

	$storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
	Get-AzureStorageBlobContent -Blob $sqlInstallBlobName -Container $containerName -Destination $destinationSqlIso -Context $storageContext
	Get-AzureStorageBlobContent -Blob $ssmsInstallBlobName -Container $containerName -Destination $destinationSSMS -Context $storageContext
	Mount-DiskImage -ImagePath d:\sqlserver.iso 
	$sqlInstallDrive = (Get-DiskImage -ImagePath "d:\sqlserver.iso" | Get-Volume).DriveLetter

	Write-Log "Mounted sql server media on " + $sqlInstallDrive
	
    $secpasswd = ConvertTo-SecureString "Workspace!DB!2017" -AsPlainText -Force
    $loginCred = New-Object System.Management.Automation.PSCredential ("wsapp", $secpasswd)

    $saPasswordSecure = $saPassword | ConvertTo-SecureString -AsPlainText -Force
    $saCreds = New-Object -TypeName pscredential -ArgumentList $saUsername, $saPasswordSecure

    $saPwd = $saPasswordSecure
    $saCred = New-Object -TypeName pscredential -ArgumentList "sa", $saPwd
     
	Write-Log "Starting SQL Server Install"
	. ./SqlStandaloneDSC

	$dataDisk = (Get-Volume -FileSystemLabel WorkspaceDB).DriveLetter
	Write-Log "The data disk drive letter is " $dataDisk

	SqlStandaloneDSC -ConfigurationData SQLConfigurationData.psd1 -LoginCredential $loginCred -SysAdminAccount $saCreds -saCredential $saCred -installDisk $sqlInstallDrive
	Start-DscConfiguration .\SqlStandaloneDSC -Verbose -wait -Force

	Write-Log "Installed SQL Server"

	Write-Log "Installing SSMS"
	Start-Process "d:\SSMS-Setup-ENU.exe" "/install /quiet /norestart /log d:\ssms-log.txt" -Wait
	Write-Log "Installed SSMS"

	Write-Log "Cleaning up"
	Dismount-DiskImage -ImagePath d:\sqlserver.iso
	Write-Log "Cleaned up"
	Remove-Item -Path $destinationSqlIso
	Remove-Item -Path $destinationSSMS
    Remove-Item -Path d:\log*.txt
    Remove-Item -Path d:\ssms-*.txt

    Write-Log "Attaching database"
    $ss = New-Object "Microsoft.SqlServer.Management.Smo.Server" "localhost"
    $ss.ConnectionContext.LoginSecure = $false
    $ss.ConnectionContext.Login = "sa"
    $ss.ConnectionContext.Password = $saPassword
    Write-Log $ss.Information.Version

	$mdf_file = "e:\AdventureWorks2012_Data.mdf"
	$mdfs = $ss.EnumDetachedDatabaseFiles($mdf_file)
	$ldfs = $ss.EnumDetachedLogFiles($mdf_file)

	$files = New-Object System.Collections.Specialized.StringCollection
    Write-Log "Enumerating mdfs"
	ForEach-Object -InputObject $mdfs {
        Write-Log $_
		$files.Add($_)
	}
    Write-Log "Enumerating ldfs"
	ForEach-Object -InputObject $ldfs {
        Write-Log $_
		$files.Add($_)
	}
	$ss.AttachDatabase("AdventureWorks", $files)

	$db = $ss.Databases['AdventureWorks']
    Write-Log $db
    Write-log $db.Users

    $wsAppLogin = $ss.Logins['wsapp']
    Write-Log $wsAppLogin

	Try
	{
		$dbusername = 'wsapp'
		$dbuser = New-Object "Microsoft.SqlServer.Management.Smo.User" $db, $dbusername
		$dbuser.Login = 'wsapp'
		$dbuser.Create()

		$db.Roles["db_datareader"].AddMember($dbuser.Name)
		$db.Roles["db_datawriter"].AddMember($dbuser.Name)
	}
	Catch
	{
		Write-Log "DB Exception"
		Write-Log $_.Exception.Message
		Write-Log $_.Exception.InnerException
	}

	Write-Log "All done!"
}
Catch
{
	Write-Log "Exception"
	Write-Log $_.Exception.Message
	Write-Log $_.Exception.InnerException
}