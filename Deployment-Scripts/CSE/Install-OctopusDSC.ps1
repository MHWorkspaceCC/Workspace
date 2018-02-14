param(

)
Function Write-Log
{
	Param ([string]$logstring)

	$Logfile = "c:\config.log"
	Add-content $Logfile -value $logstring
	Write-Host $logstring
}

Write-Log "Trusting PSGallery"
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Write-Log('Starting install of Octopus DSC')

Install-Module -Name OctopusDSC

Write-Log('Finished install of Octopus DSC')