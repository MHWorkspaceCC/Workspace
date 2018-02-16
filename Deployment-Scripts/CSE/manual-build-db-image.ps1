wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/DSC/SqlStandaloneDSC.psd1
wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/DSC/SqlConfigurationData.ps1
wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/move-dvd.ps1
wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/install-sql-server.ps1
wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/install-ssms.ps1
wget https://raw.githubusercontent.com/MHWorkspaceCC/Workspace/master/Deployment-Scripts/CSE/configure-sql-server-image.ps1

. .\configure-sql-server-image.ps1 `
    -installersStgAcctKey "RTroekJPVf2/9tMyTfJ+LTrup0IwZIDyuus13KoQX0QuH3MCTBLt0wawD0Air2bMYF03JDV0sRSYuqYypSBxbg==" `
    -installersStgAcctName "stginstallersss0p" `
    -saUserName "wsadmin" -saPassword "Workspace!DB!2018" `
    -loginUserName "wsapp" -loginPassword "Workspace!DB!2018" `
    -sysUserName "wsapp" -sysPassword = "Workspace!DB!2018"