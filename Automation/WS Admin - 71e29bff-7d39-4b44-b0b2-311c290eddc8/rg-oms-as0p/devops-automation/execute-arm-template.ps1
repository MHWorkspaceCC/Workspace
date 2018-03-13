$isDotSourced = $MyInvocation.InvocationName -eq '.' -or $MyInvocation.Line -eq ''
Write-Host $isDotSourced

function Execute-WsArmTemplate{
    param(
        [string]$templateName,
        [Hashtable]$parameters,
        [string]$resourceGroupName,
        [switch]$simulate
    )

    Write-Verbose "In:  " $MyInvocation.MyCommand

    $path = $("c:\temp\" + $templateName + ".json")

    $content = Get-ArmTemplateContent -templateName $templateName
    $content | Out-File -FilePath $path

    if (!$simulate){
		$result = New-AzureRmResourceGroupDeployment `
			-Name $name `
			-ResourceGroupName $resourceGroupName `
			-TemplateFile $path `
			-TemplateParameterObject $parameters `
			-Force -Verbose `
			-InformationAction Continue `
			-ErrorVariable errorMessages

		if ($errorMessages) {
			$exceptionMessage = 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
			Write-Output $exceptionMessage
			throw $exceptionMessage   
        }
    } else {
        Write-Verbose "Skipped deployment as the simulate flag was set"
    }
} 