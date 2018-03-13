workflow test-wf
{
    Write-Output "HI"

    InlineScript {
        Write-Output "Sourcing"
        .\core.ps1
        Write-Output "Sourced"
        Login-WsAutomation
        Write-Output "Logged-in"
    }
}