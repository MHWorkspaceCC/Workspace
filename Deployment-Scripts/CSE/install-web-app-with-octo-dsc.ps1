
#
# install_web_app_with_octo_dsc.ps1
#
param(
	[string]$octoUrl,
	[string]$octoApiKey,
	[string]$octoEnvironment
)

Function Write-Log
{
	Param ([string]$logstring)

    Add-Content -Path "c:\config.log" -Value $logstring
	Write-Host $logstring
}

Configuration WebAppConfig
{
    param ($ApiKey, $OctopusServerUrl, $Environments, $Roles, $ServerPort)

    Import-DscResource -Module OctopusDSC

    Node "localhost"
    {
        cTentacleAgent OctopusTentacle
        {
            Ensure = "Present"
            State = "Started"

            Name = "Tentacle"

			CommunicationMode = "Poll"
			ServerPort = $ServerPort
			#OctopusServerThumbprint = "E51CABA6C115C3DB0343391E58916AA7BBC5E503"

            ApiKey = $ApiKey
            OctopusServerUrl = $OctopusServerUrl
            Environments = $Environments
            Roles = $Roles

			DefaultApplicationDirectory = "C:\Applications"

			Policy = "VMSS Web Policy"
        }
    }
}

Write-Log "In configure web app"
Write-Log $("octoUrl: " + $octoUrl)
Write-Log $("octoApiKey: " + $octoApiKey)
Write-Log $("octoEnvironment: " + $octoEnvironment)

Write-Log('Staring DSC config of octopus app')

WebAppConfig -ApiKey $octoApiKey -OctopusServerUrl $octoUrl -Environments @($octoEnvironment) -Roles @("Web-VMSS") -ServerPort 10943

Write-Log('Built config - starting configuration')
Start-DscConfiguration .\WebAppConfig -Verbose -wait
