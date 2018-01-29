  param(
	[string]$installersStgAcctKey = "bB4GIR3BQI7A4EdZ1VYx38yY8ZPCthGkle38gvnQSJ9VtyBjqkzuMbBdbxxIUYeGBSZviaVVV+Pf2CQJjl9Rbw==",
	[string]$installersStgAcctName = "stginstallersws0p",
	[string]$saUserName = "wsadmin",
	[string]$saPassword = "Workspace!DB!2017",
	[string]$loginUserName = "wsapp",
	[string]$loginPassword = "Workspace!DB!2017",
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
	Write-Log("installersStgAcctName: " + $installersStgAcctName)
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

	$dataDiskExisted = $true
	$dataVolume = Get-Volume -FileSystemLabel WorkspaceDB -ErrorVariable err -ErrorAction SilentlyContinue
    if ($err -ne $null){
		$dataDiskExisted = $false
        Write-Host "Did not find data disk so creating"
        	$dataDisk = Get-Disk | `
        		Where partitionstyle -eq 'raw' | `
                Select-Object -first 1

        $dataDisk | 
		    Initialize-Disk -PartitionStyle MBR -PassThru | `
		    New-Partition -AssignDriveLetter -UseMaximumSize | `
		    Format-Volume -FileSystem NTFS -NewFileSystemLabel "WorkspaceDB" -Confirm:$false | 
		    Write-Log

	    $dataDiskLetter = (Get-Volume -FileSystemLabel WorkspaceDB).DriveLetter
        $filename = $dataDiskLetter + ":\"
        $acl = Get-Acl $filename
        Write-Host $acl
        $ar = New-Object  system.security.accesscontrol.filesystemaccessrule("everyone","FullControl","Allow")
        $acl.SetAccessRule($ar)
        Set-Acl $filename $acl	
    }

	$initVolume = $null
	if (!$dataDiskExisted){
		$err = $null
		$initVolume = Get-Volume -FileSystemLabel InitDisk -ErrorVariable err -ErrorAction SilentlyContinue
		if ($err -ne $null){
			Write-Host "Did not find init disk so creating"
			$initDisk = Get-Disk | `
				Where partitionstyle -eq 'raw' | `
				Select-Object -first 1

			$initDisk | 
				Initialize-Disk -PartitionStyle MBR -PassThru | `
				New-Partition -AssignDriveLetter -UseMaximumSize | `
				Format-Volume -FileSystem NTFS -NewFileSystemLabel "InitDisk" -Confirm:$false | 
				Write-Log
		}
	}

	$dataDiskLetter = (Get-Volume -FileSystemLabel WorkspaceDB).DriveLetter
	Write-Log("The data disk drive letter is " + $dataDiskLetter)

	$initDiskLetter = (Get-Volume -FileSystemLabel InitDisk).DriveLetter
	Write-Log("The init disk drive letter is " + $initDiskLetter)

	Write-Log("Starting configuration")

	$ssmsInstallBlobName = "SSMS-Setup-ENU.exe"
	$destinationSqlIso = "d:\sqlserver.iso"

	Write-Log("Starting copy of installer files")
	$storageContext = New-AzureStorageContext -StorageAccountName $installersStgAcctName -StorageAccountKey $installersStgAcctKey
	Write-Log("Starting copy of SQL Server ISO")
	Get-AzureStorageBlobContent -Blob $sqlInstallBlobName -Container $containerName -Destination $destinationSqlIso -Context $storageContext
    
	if (!$dataDiskExisted){
		Write-Log("Copying database backup")
		Get-AzureStorageBlobContent -Blob "av2016.bak" -Container "dbbackups" -Destination $($initDiskLetter + ":\aw2016.bak") -Context $storageContext
	}

	Write-Log("Mounting SQL Server ISO")
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

	Write-Log("Cleaning up")
	Dismount-DiskImage -ImagePath d:\sqlserver.iso
	Write-Log("Cleaned up")
	Remove-Item -Path $destinationSqlIso
    Remove-Item -Path d:\log*.txt

	Write-Log("Cofiguring database")

	Write-Log("Creating sa account")
    $ss = New-Object "Microsoft.SqlServer.Management.Smo.Server" "localhost"
    $ss.ConnectionContext.LoginSecure = $false
    $ss.ConnectionContext.Login = "sa"
    $ss.ConnectionContext.Password = $saPassword
    Write-Log($ss.Information.Version)
	<#
	if (!$dataDiskExisted){
		Write-Log("Restoring database")
		$dbCommand = "RESTORE DATABASE AdventureWorks FROM DISK = N'" + $initDiskLetter + ":\aw2016.bak' WITH MOVE 'AdventureWorks2016_Data' TO '" + $dataDiskLetter + ":\AdventureWorks2016.mdf', MOVE 'AdventureWorks2016_log' TO '" + $dataDiskLetter + ":\AdventureWorks2016.ldf',REPLACE"
		Invoke-Sqlcmd -Query $dbCommand  -ServerInstance 'localhost' -Username 'sa' -Password $saPassword
	}else{
		Write-Log "Attaching database"

		$ss = New-Object "Microsoft.SqlServer.Management.Smo.Server" "localhost"
		$ss.ConnectionContext.LoginSecure = $false
		$ss.ConnectionContext.Login = "sa"
		$ss.ConnectionContext.Password = $saPassword
		Write-Log $ss.Information.Version

		$mdf_file = $dataDiskLetter + ":\AdventureWorks2012_Data.mdf"
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
	}

	Write-Log("Checking database info")
	$db = $ss.Databases[$databaseName]
	Write-Log("The database is:")
    Write-Log($db)
	Write-Log("Database users:")
    Write-log($db.Users)

	Write-Log("Configuring database login")

	Write-Log("Configuring database user")
	if ($db.Users.Contains($loginUserName))
	{
		Write-Host "User exists, dropping"
		$db.Users[$loginUserName].Drop()
	}
	
	Write-Log("Deleting login")
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

	Write-Log("Creating user")
	$dbuser = New-Object "Microsoft.SqlServer.Management.Smo.User" $db, $loginUserName
	$dbuser.Login = $loginUserName
	$dbuser.Create()

	$db.Roles['db_datareader'].AddMember($dbuser.Name)
	$db.Roles['db_datawriter'].AddMember($dbuser.Name)

	Write-Log("All done!")
	#>
}
Catch
{
	Write-Log("Exception")
	Write-Log($_.Exception.Message)
	Write-Log($_.Exception.InnerException)
} 
