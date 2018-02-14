param(
)

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\config.log" -Value $logstring
	Write-Host $logstring
} 

Write-Log('Configuring .NET 4.5')
Install-WindowsFeature Net-Framework-Features, Net-Framework-45-Features
Write-Log("Done installing .NET 4.5")