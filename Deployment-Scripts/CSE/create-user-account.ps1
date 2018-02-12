param(
    [string]$username = "stgfiles",
    [string]$password = "aaaa"
)

Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\configure.log" -Value $logstring
	Write-Host $logstring
} 

Write-Log "Creating local user to access AZF"
$securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
New-LocalUser -Name $username -Password $securePassword -PasswordNeverExpires -UserMayNotChangePassword -AccountNeverExpires
Write-Log('User created')