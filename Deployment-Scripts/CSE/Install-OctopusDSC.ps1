#
# Install_OctopusDSC.ps1
#
Function Write-Log
{
	Param ([string]$logstring)

	$Logfile = "c:\config.log"
	Add-content $Logfile -value $logstring
}

Write-Log('Starting install of Octopus DSC')

Install-Module -Name OctopusDSC

Write-Log('Finished install of Octopus DSC')