  Function Write-Log
{
    Param ([string]$logstring)

    Add-Content -Path "c:\configure.log" -Value $logstring
	Write-Host $logstring
} 

Try
{
	Write-Log "Trusting PSGallery"
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
	Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
	Write-Log "Installing OctoDSC"

    Install-Module -Name OctopusDSC

    Write-Log("Installing SQL Server Express")

	Try{
	    iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
		Write-Log("Installed choclatey, now using it to install SQL server express")
	    choco install sql-server-express -y
		Write-Log("Done instannling sql server express")
	}
	Catch
	{
		Write-Log("Issue installing choclatey / sql server")
		Write-Log($_.Exception.Message)
		Write-Log($_.Exception.InnerException)
	}

	Write-Log("Declaring DSC")

    Configuration octoConfig
    {
        param([PSCredential] $adminCredential)

        Import-DscResource -Module OctopusDSC
           
        Node "localhost"
        {
            cOctopusServer OctopusServer
            {
                Ensure = "Present"
                State = "Started"

                # Server instance name. Leave it as 'OctopusServer' unless you have more than one instance
                Name = "OctopusServer"

                # The url that Octopus will listen on
                WebListenPrefix = "http://localhost:80"

                SqlDbConnectionString = "Server=(local)\SQLEXPRESS;Database=Octopus;Trusted_Connection=True;"

                # The admin user to create
                OctopusAdminCredential = $adminCredential

                # optional parameters
                AllowUpgradeCheck = $true
                AllowCollectionOfAnonymousUsageStatistics = $true
                ForceSSL = $false
                ListenPort = 10943
                DownloadUrl = "https://octopus.com/downloads/latest/WindowsX64/OctopusServer"
            }
        }
    }

    $cd = @{
        AllNodes = @(
            @{
                NodeName = 'localhost'
                PSDscAllowPlainTextPassword = $true
            }
        )
    }

	Write-Log("Starting OCTO install")

    $octoAdminPwdSecure = ConvertTo-SecureString "Workspace!Octo!2018" -AsPlainText -Force
    $octoAdminCreds = New-Object System.Management.Automation.PSCredential ("octo", $octoAdminPwdSecure)

    octoConfig -adminCredential $octoAdminCreds -ConfigurationData $cd
    Start-DscConfiguration -Path ".\octoConfig" -Verbose -wait -Force

	Write-Log("Finished OCTO install, starting DSC confing for auth")

    Configuration configUserNamePasswordAuth
    {
        Import-DscResource -Module OctopusDSC

        Node "localhost"
        {
            cOctopusServerUsernamePasswordAuthentication "Enable Username/Password Auth"
            {
                InstanceName = "OctopusServer"
                Enabled = $true
            }
        }
    }

	Write-Log("Running DSC for auth")
    configUserNamePasswordAuth
    Start-DscConfiguration .\configUserNamePasswordAuth -Verbose -wait
	Write-Log("All done!")
}
Catch
{
	Write-Log("Exception")
	Write-Log($_.Exception.Message)
	Write-Log($_.Exception.InnerException)
} 
 
