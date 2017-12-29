Function Write-Log
{
	Param ([string]$logstring)

	$Logfile = "c:\config.log"
	Add-content $Logfile -value $logstring
}

Write-Log "Trusting PSGallery"
powe

Write-Log("Starting installation of IIS")

Write-Log('Creating local use to access AZF')
$username = "stgfiles1wspdpr"
$password = ConvertTo-SecureString -String "L0kVane0WMkH+6PP9rpEcoUkkFCT75bJBBNtuKayyFWS+DOtARL9bofx8fBKBZ9faHFpqTT5PxTH+PowJte7rQ==" -AsPlainText -Force
New-LocalUser -Name $username -Password $password -PasswordNeverExpires -UserMayNotChangePassword -AccountNeverExpires
Write-Log('User created')

Write-Log('Configuring .NET 4.5')
Install-WindowsFeature Net-Framework-45-Features
Write-Log('Configuring Web Server, ASP.NET 4.5')
Install-WindowsFeature Web-Ftp-Server, NET-Framework-Features
Write-Log("Installing management console")
Install-WindowsFeature Web-Mgmt-Console

Write-Log('IIS config complete')