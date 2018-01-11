 Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\configure.log" -Value $logstring
	Write-Host $logstring
} 

Try
{
	Write-Log("Trusting PSGallery")
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
	Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
	
	Write-Log("Installing OctoDSC")
    Install-Module -Name OctopusDSC

	Write-Log("Sourcing installer")
	. .\install-octopus-server-with-dsc.ps1
}
Catch
{
	Write-Log("Exception")
	Write-Log($_.Exception.Message)
	Write-Log($_.Exception.InnerException)
} 
 
 
