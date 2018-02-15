<#
.SYNOPSIS  
 Deployment script for ARO Toolkit ARM Template Deployment Execution
.DESCRIPTION  
 Deployment script for ARO Toolkit ARM Template Deployment Execution
.EXAMPLE  
.\StartStopDeploy.ps1 -SubscriptionId "" -OMSAccountName "" -AutomationAccountName "" -ResourceGroupName "" -AzureLoginPassword "" -AzureLoginPassword "" -SendGridEmailAddress ""
Version History  
v1.0   - Initial Release  
#>
Param(
    [String]$SubscriptionId,
    [String]$OMSWorkspaceName,
    [String]$AutomationAccountName,
    [String]$ResourceGroupName,
    [String]$AzureLoginUserName,
    [String]$AzureLoginPassword,
    [String]$SendGridEmailAddress
)

function Decrypt-Passcode
{
    param ([string] $EncryptedText)
    return [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($EncryptedText))
}

#*************************ENTRY POINT**********************************************

#----------------------------------------------------------------------------------
#--------------------------CREATE THE LOG FILE-------------------------------------
#----------------------------------------------------------------------------------
try
{
    $formatedDate = (Get-Date).ToString('MMddyyyy-hhmmss')
    $outfile = ".\ARO-Toolkit-Marketplace\Logs\AROToolKitMP-$formatedDate.log"
    if(!(Test-Path $outfile -Type Leaf))
    {
        New-Item -Path ".\ARO-Toolkit-Marketplace\Logs" -ItemType directory -ErrorAction SilentlyContinue
        Remove-Item -Path ".\ARO-Toolkit-Marketplace\Logs" -Include *.log -Recurse
	    New-Item -Path "$outfile" -ItemType file -ErrorAction SilentlyContinue
    }

    $((Get-Date).ToString() + " Deployment Script: Execution Started!!!") | Out-File $outfile -Append

    Write-Output "Logging into Azure Subscription..." | Out-File $outfile -Append
    
    #-----L O G I N - A U T H E N T I C A T I O N-----
    $AzPassword=Decrypt-Passcode -EncryptedText $AzureLoginPassword
    $secPassword = ConvertTo-SecureString $AzPassword -AsPlainText -Force
    $AzureOrgIdCredential = New-Object System.Management.Automation.PSCredential($AzureLoginUserName, $secPassword)
    Login-AzureRmAccount -Credential $AzureOrgIdCredential
    Get-AzureRmSubscription -SubscriptionId $SubscriptionId | Select-AzureRmSubscription

    Write-Output "Successfully logged into Azure Subscription..." | Out-File $outfile -Append

    #Variables
    $depName ="StartStopVM"
    $newGUID1 = [Guid]::NewGuid() 
    $newGUID2 = [Guid]::NewGuid() 
    $newGUID3 = [Guid]::NewGuid() 
    $newGUID4 = [Guid]::NewGuid() 
    $newGUID5 = [Guid]::NewGuid() 
    $resourceGroupLocation = 'East US 2'
    $templateFilePath = ".\ARO-Toolkit-Marketplace\azuredeploy.json"
    $templateFilePath1 = ".\ARO-Toolkit-Marketplace\azuredeploy1.json"
    $parametersFilePath = ".\ARO-Toolkit-Marketplace\azuredeploy.parameters.json"
    $parametersFilePath1 = ".\ARO-Toolkit-Marketplace\azuredeploy1.parameters.json"

    #Starts everyday 6AM
    $StartTimeUTC = (Get-Date "13:00:00").AddDays(1).ToUniversalTime()
    #Stops everyday 6PM
    $StopTimeUTC = (Get-Date "01:00:00").AddDays(1).ToUniversalTime()

    # Create requested resource group
    $exists = Get-AzureRmResourceGroup -Location $resourceGroupLocation | Where-Object {$_.ResourceGroupName -eq $ResourceGroupName}
    if (!$exists) {
        Write-Output "Creating resource group '$ResourceGroupName' in location '$resourceGroupLocation'" | Out-File $outfile -Append
        New-AzureRMResourceGroup -Name $ResourceGroupName -Location $resourceGroupLocation -Force
        Start-Sleep 10
    }else {
        Write-Output "Using existing resource group '$ResourceGroupName'" | Out-File $outfile -Append
    }

    #Create the OMS workspace
    Write-Output "Creating the OMS Workspace '$OMSWorkspaceName'" | Out-File $outfile -Append
    New-AzureRmOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $OMSWorkspaceName -Location "East US" -Sku "Standard"

    #Create the Automation Account
    Write-Output "Creating the Automation Account '$AutomationAccountName'" | Out-File $outfile -Append
    New-AzureRmAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName -Location $ResourceGroupLocation

    #Create the RunAs
    $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AzureLoginUserName, $secPassword
    New-AzureRmAutomationCredential -Name "AzureCredentials" -Value $cred -AutomationAccountName $AutomationAccountName -ResourceGroupName $ResourceGroupName 


    #Link the Automation Account --> OMS Workspace for logging
    Write-Output "Linking the Automation Account and OMS for logging" | Out-File $outfile -Append
    $automationAccountId = (Find-AzureRmResource -ResourceType "Microsoft.Automation/automationAccounts" -ResourceNameContains $AutomationAccountName).ResourceId  
    $workspaceId = (Get-AzureRmOperationalInsightsWorkspace | Where-Object Name -like ('*'+$OMSWorkspaceName+'*')).ResourceId

    Set-AzureRmDiagnosticSetting -ResourceId $automationAccountId -WorkspaceId $workspaceId -Enabled $true 

    Write-Output "Updating the JSON parameter file with dynamic values..."  | Out-File $outfile -Append
        
    #**********Find and Replace logic for Key vaults******************
    [string]$str=""
    ForEach($line in  Get-Content -Path $parametersFilePath)
    {
        #*****For VSO Variales
        if ($line -match "__newGuid1__")
        {
            $line = $line -replace "__newGuid1__", $newGUID1
        }
        
        if ($line -match "__newGuid2__")
        {
            $line = $line -replace "__newGuid2__", $newGUID2
        }

        if ($line -match "__newGuid3__")
        {
            $line = $line -replace "__newGuid3__", $newGUID3
        }

        if ($line -match "__newGuid4__")
        {
            $line = $line -replace "__newGuid4__", $newGUID4
        }

        if ($line -match "__newGuid5__")
        {
            $line = $line -replace "__newGuid5__", $newGUID5
        }

        if ($line -match "__workspaceName__")
        {
            $line = $line -replace "__workspaceName__", $OMSWorkspaceName.Trim()
        }

        if ($line -match "__accountName__")
        {
            $line = $line -replace "__accountName__", $AutomationAccountName.Trim()
        }

        if ($line -match "__emailAddress__")
        {
            $line = $line -replace "__emailAddress__", $SendGridEmailAddress.Trim()
        }

        if ($line -match "__starttime__")
        {
            $line = $line -replace "__starttime__", $StartTimeUTC
        }

        if ($line -match "__stoptime__")
        {
            $line = $line -replace "__stoptime__", $StopTimeUTC
        }

        $str=$str+$line
    }

    Set-Content -Path $parametersFilePath1 -Value $str

    [string]$strTemp=""
    ForEach($line in  Get-Content -Path $templateFilePath)
    {
        if ($line -match "__Branch__")
        {
            $line = $line -replace "__Branch__", "develop"
        }

        $strTemp=$strTemp+$line
    }
    
    Set-Content -Path $templateFilePath1 -Value $strTemp

    #Splatting parameters
    $splat = @{'Name'=$depName;
            'ResourceGroupName'=$ResourceGroupName;
            'TemplateFile'=$templateFilePath1;
            'TemplateParameterFile'= $parametersFilePath1
              }

    Write-Output "Starting Deployment..." | Out-File $outfile -Append
    New-AzureRmResourceGroupDeployment @splat -verbose

    $((Get-Date).ToString() + " Deployment Script: Execution Completed!!! ") | Out-File -FilePath $outfile -Append 
}
catch
{
Write-Output "Error Occurred..." | Out-File $outfile -Append
Write-Output $_.Exception | Out-File $outfile -Append

}