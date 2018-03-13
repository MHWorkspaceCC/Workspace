. .\source-all.ps1

workflow test-core
{
    param(
    $x = 0..5
    foreach -parallel ($i in $x){
        Write-Output $i
    }
}