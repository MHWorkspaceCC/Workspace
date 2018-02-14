param(
	[switch]$www,
	[switch]$ftp,
	[switch]$mgmt,
	[switch]$aspnet45,
	[switch]$removeDefaultSite
)

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\configure.log" -Value $logstring
	Write-Host $logstring
} 

Try{
	Write-Log "Starting installation of IIS"

	if ($www){
		Write-Log("Installing Web Server")
		Install-WindowsFeature Web-Server
	}

	if ($aspnet45){
		Write-Log("Installing Asp.net 4.5")
		Install-WindowsFeature Web-Asp-Net45
	}

	if ($ftp){
		Write-Log("Installing FTP Server")
		Install-WindowsFeature Web-Ftp-Server
	}

	if ($aspnet45){
		Write-Log("Installing management console")
		Install-WindowsFeature Web-Mgmt-Console
	}

	if ($removeDefaultSite) {
		Write-Log('Removing default web site')
		Remove-Website "Default Web Site" 
	}

	Write-Log('IIS config complete')
}
Catch
{
	Write-Log("Exception")
	Write-Log($_.Exception.Message)
	Write-Log($_.Exception.InnerException)
} 