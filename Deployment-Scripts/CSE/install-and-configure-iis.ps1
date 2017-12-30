param(
	[string]$fileShareKey,
	[string]$fileStgAcctName
)

function Write-Log
{
	param ([string]$logstring)

	$Logfile = "c:\config.log"
	Add-content $Logfile -value $logstring
}

Write-Log "Starting installation of IIS"

Write-Log "Creating local user to access AZF"
$username = $fileStgAcctName
$password = ConvertTo-SecureString -String $fileShareKey -AsPlainText -Force
New-LocalUser -Name $username -Password $password -PasswordNeverExpires -UserMayNotChangePassword -AccountNeverExpires
Write-Log('User created')

Write-Log('Configuring .NET 4.5')
Install-WindowsFeature Net-Framework-45-Features
Write-Log('Configuring Web Server, ASP.NET 4.5')
Install-WindowsFeature Web-Server, Web-Asp-Net45, NET-Framework-Features
Write-Log("Installing management console")
Install-WindowsFeature Web-Mgmt-Console

Write-Log('Removing default web site')
Remove-Website "Default Web Site" 
Write-Log('IIS config complete')