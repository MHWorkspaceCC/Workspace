param(
    [string]$saPassword = "Workspace!DB!2018",
	[string]$databaseName = "AdventureWorks",
	[string]$dbBackupBlobName = "AdventureWorks2016.bak",
	[string]$dbMdfFileName = "AdventureWorks2016_Data",
	[string]$dbLdfFileName = "AdventureWorks2016_Log",
	[string]$dbBackupsStorageAccountName = "stgdbbackupsss0p",
    [string]$dbBackupsStorageAccountKey = "dMFiKWGj8AtVR1Tf4xTgWEEqdUS0wIX/iJU/VAGrDCX/G8YfkH1mZeQUDI6h0xKQWvlVwH16nDGmzNneiMP11w==",
    [string]$databaseVolumeLabel = "WorkspaceDB",
    [string]$loginUserName = "wsapp",
	[string]$loginPassword = "Workspace!DB!2018"
)

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\config.log" -Value $logstring
	Write-Host $logstring
} 

Write-Log("In configure-sql-server")
Write-Log("saPassword: " + $saPassword)
Write-Log("loginUserName: " + $loginUserName)
Write-Log("loginPassword: " + $loginPassword)
Write-Log("databaseName: " + $databaseName)
Write-Log("dbBackupBlobName: " + $databaseName)
Write-Log("dbMdfFileName: " + $dbMdfFileName)
Write-Log("dbLdfFileName: " + $dbLdfFileName)
Write-Log("dbBackupsStorageAccountName: " + $dbBackupsStorageAccountName)
Write-Log("dbBackupsStorageAccountKey: " + $dbBackupsStorageAccountKey)
Write-Log("databaseVolumeLabel: " + $databaseVolumeLabel)


Write-Log("Trusting PSGallery")
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Write-Log("Installing SqlServer Module")
Install-Module -Name SqlServer -Repository PSGallery
Import-Module SqlServer

Write-Log("Importing AzureRM")
Install-Module -Name AzureRM -Repository PSGallery

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
		New-Partition -DriveLetter F -UseMaximumSize | `
		Format-Volume -FileSystem NTFS -NewFileSystemLabel "WorkspaceDB" -Confirm:$false | 
		Write-Log

	$dataDiskLetter = (Get-Volume -FileSystemLabel WorkspaceDB).DriveLetter

    $filename = $dataDiskLetter + ":\"
    $acl = Get-Acl $filename
    Write-Host $acl
    $ar = New-Object  system.security.accesscontrol.filesystemaccessrule("everyone","FullControl","Allow")
    $acl.SetAccessRule($ar)
    Set-Acl $filename $acl	
}else{
	$dataDiskLetter = (Get-Volume -FileSystemLabel WorkspaceDB).DriveLetter
    if ($dataDiskLetter -ne "F"){
        $dataDisk = Get-Disk | `
        	Where partitionstyle -eq 'MBR' | `
            Select-Object -last 1            
        # move the CD from F to G
        $drv = Get-WmiObject win32_volume -filter 'DriveLetter = "F:"'
        $drv.DriveLetter = "G:"
        $drv.Put()

        # put the database disk on F:
        Get-Partition -DiskNumber $dataDisk.DiskNumber | Set-Partition -NewDriveLetter F
    }
}

$dbDriveLetter = (Get-Volume -FileSystemLabel WorkspaceDB).DriveLetter
$mdfPath = $dbDriveLetter + ":\" + $dbMdfFileName + ".mdf"
$attaching = [System.IO.File]::Exists($mdfPath) 

$ss = New-Object "Microsoft.SqlServer.Management.Smo.Server" "localhost"
$ss.ConnectionContext.LoginSecure = $false
$ss.ConnectionContext.Login = "sa"
$ss.ConnectionContext.Password = $loginPassword

if (!$attaching){
    Write-Log("Restoring database")

    Write-Log("Copying database backup")
	$backupStorageContext = New-AzureStorageContext -StorageAccountName $dbBackupsStorageAccountName -StorageAccountKey $dbBackupsStorageAccountKey
	Get-AzureStorageBlobContent -Blob $dbBackupBlobName -Container "current" -Destination $($dbDriveLetter + ":\" + $dbBackupBlobName) -Context $backupStorageContext

    $dbCommand = "RESTORE DATABASE " + $databaseName + " FROM DISK = N'" + $($dbDriveLetter + ":\" + $dbBackupBlobName) + "' WITH MOVE '" + $dbMdfFileName + "' TO '" + $dbDriveLetter + ":\" + $dbMdfFileName + ".mdf', MOVE '" + $dbLdfFileName + "' TO '" + $dbDriveLetter + ":\" + $dbMdfFileName + ".ldf',REPLACE"
    Write-Log($dbCommand)
    Invoke-Sqlcmd -Query $dbCommand  -ServerInstance 'localhost' -Username 'sa' -Password $saPassword
    Write-Log("Restore complete")

    Write-Log("Deleting backup")
    Remove-Item -Path $($dbDriveLetter + ":\" + $dbBackupBlobName) 
}else{
    Write-Log "Attaching database"

	$mdfs = $ss.EnumDetachedDatabaseFiles($mdfPath)
	$ldfs = $ss.EnumDetachedLogFiles($mdfPath)

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
	$ss.AttachDatabase($databaseName, $files)
}

Write-Log("Checking database info")
$db = $ss.Databases[$databaseName]
Write-Log("The database is:")
Write-Log($db)
Write-Log("Database users:")
Write-log($db.Users)

Write-Log("Configuring database login")
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

Write-Log("Assigning roles")
$db.Roles['db_datareader'].AddMember($dbuser.Name)
$db.Roles['db_datawriter'].AddMember($dbuser.Name)

Write-Log("Done configure-sql-server") 
