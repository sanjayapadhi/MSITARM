param(
[String]$AzureSPN = ‘',
[String]$AzureSecret='',
[String]$verbose = "true"
)
if($verbose.ToLower() -eq "true")
{
    $VerbosePreference = "continue"
}

#import DeploymentLib module
$scriptPathObj=Get-Item -Path ($MyInvocation.MyCommand.Path)
Write-Verbose "importing the module ($scriptPathObj.Directory.Parent.FullName)" 
Import-Module ([string]::Format("{0}\DeploymentAutomation\DeploymentLib.ps1", $scriptPathObj.Directory.Parent.FullName))

#get managed app configuration
$cptarmConfig=Get-CPTArmConfig -branchName ($env:BUILD_SOURCEBRANCHNAME) -scriptPath ($MyInvocation.MyCommand.Path)

#spn login
Write-Verbose "Logging into azure......"
login-spn -AzureSecret $AzureSecret `
    -AzureSPN $AzureSPN `
    -subscription $cptarmConfig.Subcription `
    -verbose 

#upload CPT-ARM nested templates
$arrFilesToUpload=getblocbcontent-cptarm -branchName $env:BUILD_SOURCEBRANCHNAME `
    -prefixFilepath (Get-SourceCodeDirPath -scriptPath ($MyInvocation.MyCommand.Path)) 

$result=UploadTemplates-Storageblob -rgName $cptarmConfig.ResourceGroup `
            -storageAccName $cptarmConfig.StorageAccount `
            -containerName $cptarmConfig.Container `
            -filePathList $arrFilesToUpload `
            -verbose

if($result -eq $false)
{
    throw "Failed in uploading SI-HDC-CPT-ARM templates to azure blob......"
}
