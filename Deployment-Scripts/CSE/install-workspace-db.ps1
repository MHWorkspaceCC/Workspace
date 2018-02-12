param(
    [string]$saPassword = "Workspace!!DB!2018",
	[string]$databaseName = "AdventureWorks",
	[string]$dbBackupBlobName = "AdventureWorks2016.bak",
	[string]$dbMdfFileName = "AdventureWorks2016_Data",
	[string]$dbLdfFileName = "AdventureWorks2016_Log",
	[string]$dbBackupsStorageAccountName = "stgdbbackupsss0p",
    [string]$dbBackupsStorageAccountKey = "MjxzzdLwmgeB6emUEcepOEko+SYiZtPE578BMXFeSMQnXHXO7PJm8EyhM9Ndk1afp94wZ55vXp656li6BlD+6w==",
    [string]$databaseVolumeLabel = "WorkspaceDB",
    [string]$loginUserName = "wsapp",
	[string]$loginPassword = "Workspace!DB!2018"
)

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\configure.log" -Value $logstring
	Write-Host $logstring
} 

$volume = Get-Volume -FileSystemLabel $databaseVolumeLabel -ErrorVariable err -ErrorAction SilentlyContinue
if ($volume -eq $null){
    throw "Did not find volume: " + $databaseVolumeLabel
}

$dbDriveLetter = $volume.DriveLetter

Write-Log("Trusting PSGallery")
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Write-Log("Installing SqlServer")
Install-Module -Name SqlServer -Repository PSGallery
Import-Module SqlServer

$mdfPath = $dbDriveLetter + "\" + $dbMdfFileName + ".mdf"
$attaching = [System.IO.File]::Exists($mdfPath)

$ss = New-Object "Microsoft.SqlServer.Management.Smo.Server" "localhost"

if (!$attaching){
    Write-Log("Restoring database")

    Write-Log("Copying database backup")
	$backupStorageContext = New-AzureStorageContext -StorageAccountName $dbBackupsStorageAccountName -StorageAccountKey $dbBackupsStorageAccountKey
	Get-AzureStorageBlobContent -Blob $dbBackupBlobName -Container "current" -Destination $($dbDriveLetter + ":\" + $dbBackupBlobName) -Context $backupStorageContext

    $dbCommand = "RESTORE DATABASE " + $databaseName + " FROM DISK = N'" + $($dbDriveLetter + ":\" + $dbBackupBlobName) + "' WITH MOVE '" + $dbMdfFileName + "' TO '" + $dbDriveLetter + ":\" + $dbMdfFileName + ".mdf', MOVE '" + $dbLdfFileName + "' TO '" + $dbDriveLetter + ":\" + $dbMdfFileName + ".ldf',REPLACE"
    Write-Log($dbCommand)
    Invoke-Sqlcmd -Query $dbCommand  -ServerInstance 'localhost' -Username 'sa' -Password $saPassword
    Write-Log("Restore complete")
}else{
    Write-Log "Attaching database"
    $ss.ConnectionContext.LoginSecure = $false
    $ss.ConnectionContext.Login = "sa"
    $ss.ConnectionContext.Password = $loginPassword
    Write-Log $ss.Information.Version

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

Write-Log("Done installing database")