function Update-BranchName
{
    param([String]$sourceFilePath,
        [String] $destFilePath,
        [string] $branchName)
    
    if($branchName.ToLower() -eq "develop" -or `
        $branchName.ToLower() -eq "beta" -or `
        $branchName.ToLower() -eq "master")
    {
        $tempContent=Get-Content -Path $sourceFilePath
        for($icount=0;$icount -lt $tempContent.Count; ++$icount)
        {
            $lineStr=$tempContent[$icount].Trim()
            $arrStr=$lineStr.Split(":")
            if($arrStr.Count -eq 2 -and `
                $arrStr[0].ToLower() -eq '"branch"')
            {
                switch($branchName)
                {
                    "develop" {
                        $tempContent[$icount] = '"branch":"develop",'
                        break
                    }
                    "beta" {
                        $tempContent[$icount] = '"branch":"beta",'
                        break
                    }
                    "master" {
                        $tempContent[$icount] = '"branch":"master",'
                        break
                    }
                    default {break;}
                }
                break;
            }
        }

        $tempContent | Out-File $destFilePath -Encoding utf8 -Force
    }
    else
    {
        throw "Bad branch name"
    }
}

function Get-SourceCodeDirPath
{
    param([String]$scriptPath)
    $scriptPathObj=Get-Item -Path $scriptPath
    
    return $scriptPathObj.Directory.Parent.FullName
}

function Get-DeploymentConfigPath
{
    param([String]$scriptPath)

    $sourceDir = Get-SourceCodeDirPath -scriptPath $scriptPath
    
    $DeploymentConfigPath=[string]::Format("{0}\DeploymentAutomation\DeployConfig.json", $sourceDir)
    return $DeploymentConfigPath
}

function Get-ManagedAppConfig
{
    param([String]$scriptPath,
        [String]$branchName)

    $DepConfigObj = Get-Content (Get-DeploymentConfigPath -scriptPath $scriptPath) | Out-String | ConvertFrom-Json
    $result = $null
    switch($branchName)
    {
        "develop" 
        {
            $result = $DepConfigObj.DevelopBranch.ManagedApplication;
            break
        }
        "beta" 
        {
            $result = $DepConfigObj.BetaBranch.ManagedApplication;
            break
        }
        "master" 
        {
            $result = $DepConfigObj.MasterBranch.ManagedApplication;
            break
        }
        default{break}
    }

    return $result
}

function Get-CPTArmConfig
{
    param([String]$scriptPath,
        [String]$branchName)

    $DepConfigObj = Get-Content (Get-DeploymentConfigPath -scriptPath $scriptPath) | Out-String | ConvertFrom-Json
    $result = $null
    switch($branchName)
    {
        "develop" 
        {
            $result = $DepConfigObj.DevelopBranch.CPTArm
            break
        }
        "beta" 
        {
            $result = $DepConfigObj.BetaBranch.CPTArm;
            break
        }
        "master" 
        {
            $result = $DepConfigObj.MasterBranch.CPTArm;
            break
        }
        default{break}
    }

    return $result
}

function Get-ManagedAppDirPath
{
    param([String]$scriptPath)

    $sourceDir = Get-SourceCodeDirPath -scriptPath $scriptPath
    
    $ManagedAppDirPath=[string]::Format("{0}\ManagedApplications", $sourceDir)
    return $ManagedAppDirPath
}

function Get-NestedTemplatePath
{
    param([String]$scriptPath)

    $sourceDir = Get-SourceCodeDirPath -scriptPath $scriptPath
    $ManagedAppDirPath=[string]::Format("{0}\all-nested", $sourceDir)
    return $ManagedAppDirPath

}

function Get-NestedScriptPath
{
    param([String]$scriptPath)

    $sourceDir = Get-SourceCodeDirPath -scriptPath $scriptPath
    
    $ManagedAppDirPath=[string]::Format("{0}\all-scripts", $sourceDir)
    return $ManagedAppDirPath

}

function Update-TemplateJsonFile
{
    param([String]$jsonFromPath,
        [String]$BranchName =$null,
        [String]$StorageAccountName =$null,
        [String]$ContainerName =$null,
        [String]$jsonToPath =$null)
    
    $tempText=Get-Content  $jsonFromPath 
    
    if($BranchName -ne $null -and $BranchName.Length -gt 0)
    {
        $tempText=$tempText.Replace("#branch#",$BranchName)
    }
    if($StorageAccountName -ne $null -and $StorageAccountName.Length -gt 0)
    {
        $tempText=$tempText.Replace("#StorageAccountName#",$StorageAccountName)
    }
    if($ContainerName -ne $null -and $ContainerName.Length -gt 0)
    {
        $tempText=$tempText.Replace("#ContainerName#",$ContainerName)
    }
   
    $tempText | Out-File  $jsonToPath -Encoding string -Force
}

function login-spn
{
    param ([string] $AzureSecret,
        [string] $AzureSPN,
        [string] $subscription,
        [string] $TenantId= "72f988bf-86f1-41af-91ab-2d7cd011db47",
        [switch]$verbose)
    
    if($verbose) 
    {
        $oldverbose = $VerbosePreference
        $VerbosePreference = "continue" 
    }
    try
    {
        #log-in into azure
        $AzureSecStr = ConvertTo-SecureString $AzureSecret -AsPlainText -Force
        $Azurecred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AzureSPN, $AzureSecStr
        $result = Login-AzureRmAccount -Credential $Azurecred -ServicePrincipal -TenantId $Tenantid 

        Write-Verbose $result
        if($result -ne $null)
        {
            $result = Select-AzureRmSubscription -SubscriptionName $subscription  
            Write-Verbose $result
            if($result -ne $null)
            {
                return $true
            }
            else
            {
                return $false
            }
        }
        else
        {
            return $false
        }
    }
    catch
    {
        Write-Verbose "Exception occured. Exp->$_.Exception.Message"
        return $false
    }
    finally
    {
        $VerbosePreference = $oldverbose
    }
}

function uplodate-AzModules
{
    Update-Module "AzureRM.Resources" -Force
}

function UploadTemplates-Storageblob
{
    param ([string] $rgName,
        [string] $storageAccName,
        [string] $containerName,
        [string[]] $filePathList,
        [switch]$verbose)

    if($verbose) 
    {
        $oldverbose = $VerbosePreference
        $VerbosePreference = "continue" 
    }
    try
    {
        Write-Verbose "Came to UploadTemplates-Storageblob"
        Write-Verbose ([string]::Format("RG->{0}, Storage->{1}; container->{2}",$rgName,$storageAccName,$containerName))

        Set-AzureRmCurrentStorageAccount -ResourceGroupName $rgName -Name $storageAccName
     
        for ($icount=0; $icount -lt $filePathList.Count; ++$icount)
        {
            $arrStr=$filePathList[$icount].Split(",")
            $fileURI=$arrStr[0]
            $blob = $arrStr[1]
            
            Write-Verbose "Uploading the file $fileURI to the blob $blob"
            #upload the blob
            $result= Set-AzureStorageBlobContent -ErrorAction Stop -Container $containerName -Blob $blob -File $fileURI -Force

        }

        return $true
    }
    catch
    {
        Write-Verbose "Exception occured. Exp->$_.Exception.Message"
        return $false
    }
    finally
    {
        $VerbosePreference = $oldverbose
    }
}

function getblocbcontent-cptarmdeploy
{
    param ([string] $prefixFilepath,
        [string] $branchName
        )

    $folderNameList=@()

    $folderNameList+="301-singlevm-windows-server-manageddisk-build"
    $folderNameList+="301-multiplevm-windows-server-manageddisk-build"
    $folderNameList+="301-Multi-VM-WebILB-manageddisk-build"

    $folderNameList+="301-singlevm-mssqlserver-standardstorage-manageddisk-build"
    $folderNameList+="301-singlevm-mssqlserver-premiumstorage-manageddisk-build"
    $folderNameList+="301-singlevm-mssqlserver-premiumconfigmanageddisk-build"

    $folderNameList+="301-multiplevm-mssqlserver-standardstorage-manageddisk-build"
    $folderNameList+="301-multiplevm-mssqlserver-premiumstorage-manageddisk-build"
    $folderNameList+="301-multiplevm-mssqlserver-prem-configmanageddisk-build"

    $folderNameList+="301-multiplevm-sqlilb-std-manageddisk-build"
    $folderNameList+="301-multiplevm-sqlilb-prem-manageddisk-build"
    $folderNameList+="301-multiplevm-sqlilb-premconfigmanageddisk-build"
    
    
    $arrFileList=@()

    for($iCount=0; $iCount -lt $folderNameList.Length; ++$iCount)
    {
        $sourceFilePath = [string]::Format("{0}\{1}\azuredeploy.json",$prefixFilepath,$folderNameList[$iCount])
        $destFilePath = [string]::Format("{0}\{1}",$branchName,$folderNameList[$iCount].Replace("-","_").Replace(" ",""))
        $arrFileList+=[string]::Format("{0},{1}.json",$sourceFilePath,$destFilePath)
    }

    return $arrFileList
}

function getblocbcontent-cptarm
{
    param ([string] $prefixFilepath,
        [string] $branchName
        )

    $arrFileList=@()

    #get all files in all-nested folder
    $sourceDir=[string]::Format("{0}\all-nested",$prefixFilepath)
    $arrFilesInDir=Get-ChildItem -Path $sourceDir 
    
    for($icount=0; $icount -lt $arrFilesInDir.Count; ++$icount)
    {
        $sourceFilePath = $arrFilesInDir[$icount].FullName
        $destFilePath = [string]::Format("{0}\all-nested\{1}",$branchName,$arrFilesInDir[$icount].Name)
        $arrFileList+=[string]::Format("{0},{1}",$sourceFilePath,$destFilePath)
    }

    #get all files in all-scripts folder
    $sourceDir=[string]::Format("{0}\all-scripts",$prefixFilepath)
    $arrFilesInDir=Get-ChildItem -Path $sourceDir 
    
    for($icount=0; $icount -lt $arrFilesInDir.Count; ++$icount)
    {
        $sourceFilePath = $arrFilesInDir[$icount].FullName
        $destFilePath = [string]::Format("{0}\all-scripts\{1}",$branchName,$arrFilesInDir[$icount].Name)
        $arrFileList+=[string]::Format("{0},{1}",$sourceFilePath,$destFilePath)
    }

    return $arrFileList
}

function Create-zipcontent
{
    param ([string] $SourceDir,
        [string] $zipFilePath
        )

    If(Test-path $zipFilePath) {Remove-item $zipFilePath}

    Add-Type -assembly "system.io.compression.filesystem"

    [io.compression.zipfile]:: CreateFromDirectory($SourceDir, $zipFilePath)

    If(Test-path $zipFilePath)
    {
        return $true
    }
    else
    {
        return $false
    }
}

function update-maintemplate
{
    param ([string] $sourceDir,
        [string] $branchName,
        [PSObject] $managedAppConfig,
        [switch]$verbose)
    if($verbose) 
    {
        $oldverbose = $VerbosePreference
        $VerbosePreference = "continue" 
    }
    try
    {
        $arrDir=Get-ChildItem -Path $sourceDir -Directory
        if($arrDir -ne $null)
        {
           $arrFileList=@()
           for($icount=0; $icount -lt $arrDir.count;$icount++)
           {
                $sourceDirPath=$arrDir[$icount].FullName
                $pathToMainTemplate="$sourceDirPath\mainTemplate.json"

                if(Test-Path -Path $pathToMainTemplate)
                {
                    #update json file with branch name and other details
                    Write-Verbose "Updating the maintemplate->$pathToMainTemplate"
                    Update-TemplateJsonFile -jsonFromPath $pathToMainTemplate `
                        -BranchName $branchName `
                        -StorageAccountName $managedAppConfig.StorageAccount `
                        -ContainerName $managedAppConfig.Container `
                        -jsonToPath $pathToMainTemplate
                }
                else
                {
                    Write-Verbose "$pathToMainTemplate is not found to update branch,storage account details"
                }
           }
        }
    }
    catch
    {
        Write-Verbose "Exception occured. Exp->$_.Exception.Message"
        return $false
    }
    finally
    {
        $VerbosePreference = $oldverbose
    }
}

function Create-ManagedAppPackage
{
    param ([string] $sourceDir,
        [string] $branchName,
        [PSObject] $managedAppConfig,
        [switch]$verbose)
    if($verbose) 
    {
        $oldverbose = $VerbosePreference
        $VerbosePreference = "continue" 
    }
    try
    {
        $arrDir=Get-ChildItem -Path $sourceDir -Directory
        if($arrDir -ne $null)
        {
           $arrFileList=@()
           for($icount=0; $icount -lt $arrDir.count;$icount++)
           {
                $sourceDirPath=$arrDir[$icount].FullName
                $destFilePath=[string]::Format("{0}.zip", `
                    $arrDir[$icount].FullName)

                Write-Verbose "Creating the zip.. $sourceDirPath -> $destFilePath"
                Create-zipcontent -SourceDir $sourceDirPath -zipFilePath $destFilePath

                #package zip file
                $sourcePackagePath = $destFilePath
                $destPackagePath = [string]::Format("{0}\{1}.zip",$branchName,$arrDir[$icount].Name)
                $arrFileList+=[string]::Format("{0},{1}",$sourcePackagePath,$destPackagePath)
                
                #consolidated json file
                $consolidatedJsonPath = [string]::Format("{0}.json", $arrDir[$icount].FullName)
                $destJsonPath = [string]::Format("{0}\{1}.json",$branchName,$arrDir[$icount].Name)
                $arrFileList+=[string]::Format("{0},{1}",$consolidatedJsonPath,$destJsonPath)

                #update json file with branch name and other details
                Update-TemplateJsonFile -jsonFromPath $consolidatedJsonPath `
                    -BranchName $branchName `
                    -StorageAccountName $managedAppConfig.StorageAccount `
                    -ContainerName $managedAppConfig.Container `
                    -jsonToPath $consolidatedJsonPath
           }

           
           Write-Verbose "Invoking UploadTemplate method to upload packages. UploadFileList->$arrFileList"
           #upload package
           UploadTemplates-Storageblob -rgName $managedAppConfig.ResourceGroup `
                -storageAccName $managedAppConfig.StorageAccount `
                -containerName $managedAppConfig.Container `
                -filePathList $arrFileList `
                -verbose
        }
        else
        {
            Write-Verbose "There are no sub directories exist..."
        }
    }
    catch
    {
        Write-Verbose "Exception occured. Exp->$_.Exception.Message"
        return $false
    }
    finally
    {
        $VerbosePreference = $oldverbose
    }
}

function Create-ManagedAppDefinition
{
    param ([string] $branchName,
        [string] $sourceDir,
        [PSObject] $managedAppConfig,
        [switch]$verbose)

    if($verbose) 
    {
        $oldverbose = $VerbosePreference
        $VerbosePreference = "continue"
    }
    try
    {
        for($icount = 0; $icount -lt $managedAppConfig.Details.Count; ++$icount)
        {
            if($managedAppConfig.Details[$icount].Enabled -eq $true)
            {
                $authorization = [string]::Format("{0}:{1}",$managedAppConfig.Details[$icount].AuthrizationGroupID,$managedAppConfig.Details[$icount].AuthrizationRoleID)
            
                $FileUri = [string]::Format("https://{0}.blob.core.windows.net/{1}/{2}/{3}.zip", `
                    $managedAppConfig.StorageAccount, `
                    $managedAppConfig.Container, `
                    $branchName, `
                    $managedAppConfig.Details[$icount].VsoName)

                Write-Verbose "FileURI->$FileUri"
                $logInfo=[string]::Format("Now checking the presense of Managed app ->{0}",$managedAppConfig.Details[$icount].Name)
                Write-Verbose $logInfo

                #check if managed app is already available
                $mngApp=$null
                try
                {
                    $mngApp=Get-AzureRmManagedApplicationDefinition -ResourceGroupName $managedAppConfig.ResourceGroup `
                                -Name $managedAppConfig.Details[$icount].Name `
                                -ErrorAction SilentlyContinue
                }
                catch
                {
                    Write-Verbose "Exception occured.But this exception is handled here... Exp->$_.Exception.Message"
                }
                if ($mngApp -ne $null)
                {
                    Write-Verbose "Managed app is present in the RG. Now deleteing....."
                    $status = $false
                    #delete the managed app
                    $status = Remove-AzureRmManagedApplicationDefinition -ResourceGroupName $managedAppConfig.ResourceGroup `
                                -Name $managedAppConfig.Details[$icount].Name `
                                -Force `
                                -ErrorAction Stop
                }
                if(($mngApp -ne $null -and $status -eq $true) -or ($mngApp -eq $null))
                {
                    Write-Verbose "Creating the managed app....."
                    #create managed app
                    $status = New-AzureRmManagedApplicationDefinition -Name $managedAppConfig.Details[$icount].Name `
                                -ResourceGroupName $managedAppConfig.ResourceGroup `
                                -DisplayName $managedAppConfig.Details[$icount].DisplayName `
                                -Description $managedAppConfig.Details[$icount].Description `
                                -Location $managedAppConfig.Details[$icount].Location `
                                -LockLevel ReadOnly `
                                -PackageFileUri $FileUri `
                                -Authorization $authorization `
                                -ErrorAction Stop `
                                -Verbose
                }
                else
                {
                    throw "Exception occured in deleting existing managed app..."
                }
            }
        }
        return $true
    }
    catch
    {
        Write-Verbose "Exception occured. Exp->$_.Exception.Message"
        return $false
    }
    finally
    {
        $VerbosePreference = $oldverbose
    }
}