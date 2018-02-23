wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/move-dvd.ps1 -OutFile move-dvd.ps1
wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/install-net45.ps1 -OutFile install-net45.ps1
wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/install-iis.ps1 -OutFile install-iis.ps1
wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/install-octopusdsc.ps1 -OutFile install-octopusdsc.ps1
wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/configure-web-server-image.ps1 -OutFile configure-web-server-image.ps1

. .\configure-web-server-image.ps1
Remove-Item -Path c:\config.log