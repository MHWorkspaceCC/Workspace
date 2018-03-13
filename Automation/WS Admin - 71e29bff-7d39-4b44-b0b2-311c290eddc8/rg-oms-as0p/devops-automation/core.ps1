if (!$coreps1_sourced) {
    $coreps1_sourced = $true
    
    Write-Output "core.ps1 sourced"

    Add-Type -AssemblyName System.Collections

    $resourceCategories = @(
	    "web"
	    "ftp"
	    "jump"
	    "admin"
	    "db"
	    "svc"
	    "pips"
	    "nsgs"
	    "vnet"
    )

    $wsAcctInfo = @{
	    "profileFile" = "workspacecc.json"
	    "subscriptions" = @{
		    "a" = @{
			    "subscriptionName" = "WS Admin"
			    "subscriptionID" = "71e29bff-7d39-4b44-b0b2-311c290eddc8"
		    }
		    "t" = @{
			    "subscriptionName" = "WS Test"
			    "subscriptionID" = "3f7acc9e-d55d-4463-a7a8-cd8d9b01de40"
		    }
		    "d" = @{
			    "subscriptionName" = "WS Dev"
			    "subscriptionID" = "8cc982bb-0877-4c51-aa28-6325a012e486"
		    }
		    "s" = @{
			    "subscriptionName" = "WS Data - Platform"
			    "subscriptionID" = "687dd9cb-d46c-4dcc-abd1-6cb3d19ab063"
		    }
	    }
    }

    $environments = @{
	    "validCodes" = "pdtsqc"
	    "codeNameMap" = @{
		    p = "Production"
		    d = "Development"
		    t = "Test"
		    s = "Staging"
		    q = "QA"
		    c = "Common"
	    }
	    "cidrValues" = @{
		    p = 0
		    d = 1 
		    t = 2
		    s = 3
		    q = 4
		    c = 5
	    }
    }

     $facilities = @{
	    "validCodes" = "pd"
	    "codeNameMap" = @{
		    p = "Primary"
		    d = "Disaster Recovery"
	    }
	    "cidrValues" = @{
		    p = 0 
		    d = 1 
	    }
	    "locations" = @{
		    p = "westus"
		    d = "eastus"
	    }
        "peers" = @{
            "p" = "d"
            "d" = "p"
        }
    }

    $connected = $false
    $connectionName = "AzureRunAsConnection"

    function Calculate-VnetCidrPrefix{
        param(
            [string]$environment, 
            [int]$slot, 
            [string]$facility
        )
		$cidr1 = $environments['cidrValues'][$environment] 
		$cidr2 = $slot
		$cidr3 = $facilities['cidrValues'][$facility]
		$cidrValue = ($cidr1 -shl 5) + ($cidr2 -shl 2) + $cidr3

		return "10." + ("{0}" -f $cidrValue) + "."
	}

    Function Login-WsAutomation{

        try
        {
            # Get the connection "AzureRunAsConnection 
            Write-Output "Getting run as service principal"

            $servicePrincipalConnection = Get-AutomationConnection -Name $connectionName  
            Write-Output $servicePrincipalConnection

            Write-Output "Logging in to Azure..."

            Add-AzureRmAccount `
               -ServicePrincipal `
               -TenantId $servicePrincipalConnection.TenantId `
               -ApplicationId $servicePrincipalConnection.ApplicationId `
               -CertificateThumbprint $servicePrincipalConnection.CertificateThumbprint 

            Write-Output "Logged in"
            $connected = $true
        }
        catch {
            if (!$servicePrincipalConnection)
            {
                $ErrorMessage = "Connection $connectionName not found."
                throw $ErrorMessage
            } else {
                Write-Error -Message $_.Exception
                throw $_.Exception
            }
        }
    }

    [System.Collections.Stack]$contextStack = [System.Collections.Stack]::new()
    $currentContext = $null

    Function Set-WsContext {
        param(
            [string]$subscription,
            [string]$environment,
            [int]$slot,
            [string]$facility
        )

        #TODO: Validate parameters

        $environmentCode = $environment + $slot.ToString()

        $newContext = @{
            "subscription" = $subscription
            "environment" = $environment
            "slot" = $slot
            "environmentCode" = $environmentCode
            "facility" = $facility
            "primary" = $facility
            "secondary" = $facilities["peers"][$facility]
            "primaryResourcePostix" = $subscription + $environmentCode + $facility
            "secondaryResourcePostix" = $subscription + $environmentCode + $facilities["peers"][$facility]
            "primaryCidrPrefix" = Calculate-VnetCidrPrefix -environment $environment -slot $slot -facility $facility
            "secondaryCidrPrefix" = Calculate-VnetCidrPrefix -environment $environment -slot $slot -facility $facility
        }

        $currentContext = $newContext
    }

    function Get-WsFacility{
        param(
            [switch]$secondary
        )

        if (!$secondary) { return $currentContext["primary"] }
        return $currentContext["secondary"]
    }

    function Get-WsResourcePostfix{
        param(
            [switch]$secondary
        )

        if (!$secondary) { return $currentContext["primaryResourcePostfix"] }
        return $currentContext["secondaryResourcePostfix"]
    }

    function Get-WsLocation{
        param(
            [switch]$secondary
        )
        if (!$secondary) { return $facilityLocations[$currentContext["primary"]] }
        return $facilityLocations[$currentContext["secondary"]]
    }

    function Add-WsTagsToParameters{
        param(
            [Hashtable]$parameters,
            [string]$role,
            [switch]$secondary
        )

        $parameters["environment"] = $currentContext["environment"]
        $parameters["environmentCode"] = $currentContext["environment"] + $currentContext["slot"].ToString()
        $parameters["facility"] = Get-WsFacility -secondary:$secondary
        $parameters["instance"] = $currentContext["slot"].ToString()
        $parameters["subscriptionCode"] = $currentContext["subscription"]
        $parameters["role"] = $role
        $parameters["resourceNamePostfix"] = Get-WsResourcePostfix -secondary:$secondary
        $parameters["location"] = Get-WsLocation -secondary:$secondary
    }

    function Get-WsResourceGroupName{
        param(
            [string]$category,
            [switch]$secondary
        )
        if (!$secondary) { $postfix = $currentContext["primaryResourcePostix"] }
        else { $postfix = $currentContext["secondaryResourcePostix"] }
        return "rg-" + $category + "-" + $postfix
    }

     function Get-VnetCidrPrefix{
        param(
            [switch]$secondary
        )

        if (!$secondary) { return $currentContext["primaryCidrPrefix"] }
        return $currentContext["secondaryCidrPrefix"]
    }
}