param(
	[string]$installersStgAcctKey = "RTroekJPVf2/9tMyTfJ+LTrup0IwZIDyuus13KoQX0QuH3MCTBLt0wawD0Air2bMYF03JDV0sRSYuqYypSBxbg==",
	[string]$installersStgAcctName = "stginstallersss0p",
	[string]$saUserName = "wsadmin",
	[string]$saPassword = "Workspace!DB!2018",
	[string]$loginUserName = "wsapp",
	[string]$loginPassword = "Workspace!DB!2018",
	[string]$containerName = "sqlserver",
	[string]$sqlInstallBlobName = "en_sql_server_2016_enterprise_with_service_pack_1_x64_dvd_9542382.iso",
	[string]$ssmsInstallBlobName = "SSMS-Setup-ENU.exe",
	[string]$destinationSqlIso = "d:\sqlserver.iso",
	[string]$destinationSSMS = "d:\SSMS-Setup-ENU.exe",
	[string]$databaseName = "AdventureWorks",
	[string]$dbBackupBlobName = "AdventureWorks2016.bak",
	[string]$dbMdfFileName = "AdventureWorks2016_Data",
	[string]$dbLdfFileName = "AdventureWorks2016_Log",
	[string]$dbBackupsStorageAccountName = "stgdbbackupsss0p",
    [string]$dbBackupsStorageAccountKey = "MjxzzdLwmgeB6emUEcepOEko+SYiZtPE578BMXFeSMQnXHXO7PJm8EyhM9Ndk1afp94wZ55vXp656li6BlD+6w==",
    [string]$fileShareKey="a",
	[string]$fileStgAcctName="b",
	[string]$fileShareName="c"
)

.\move-dvd.ps1
.\init-data-disk.ps1 -driveLabel "WorkspaceDB" -driveLetter F
.\set-drive-permissions.ps1 -driveLabel "WorkspaceDB"
.\install-net45.ps1
.\install-iis.ps1 -www -ftp -aspnet45 -mgmt -removeDefaultSite
.\create-user-account -username $fileStgAcctName -password $fileShareKey
.\install-sql-server.ps1 
.\install-smss.ps1
.\install-workspace-db.ps1