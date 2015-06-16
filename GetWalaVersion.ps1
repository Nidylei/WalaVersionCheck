param ([string] $SubscriptionName, [string] $ImageLabelPath, [string] $VmSize)
Import-Module "C:\Program Files (x86)\Microsoft SDKs\Azure\PowerShell\ServiceManagement\Azure\*.psd1"

#$StorAccount = ”ciwestus”
#$VmSize = "Small"
#$Cert = Get-PfxCertificate -FilePath .\ostcci.cer
#$sshPath = '/home/' + $UserName + '/.ssh/authorized_keys'

$UserName = "azureuser"
$Passwd = "P@ssw0rd01"
$StorAccount = "feile" + (Get-Date).Month + (Get-Date).Day + (Get-Date).Hour + (Get-Date).Minute + (Get-Date).Second
$Cert = Get-Item Cert:\CurrentUser\My\35D3EEE321B6A1300C684B5550812CB7489E7115


<#
 check the param is valid or not
#>
    
if(!(Test-Path $ImageLabelPath))
{
    Write-Host "Error: The Path not exist" -ForegroundColor Red
    return;
}

$ImageArray=[array](Get-Content $ImageLabelPath)
if($ImageArray.Length -eq 0)
{
    Write-Host "Error: The file ""$ImageLabelPath"" is empty or invalid" -ForegroundColor Red
    return;
}


if($SubscriptionName.Equals("OSTC Shanghai Test"))
{
    $SubscriptionID = "4be8920b-2978-43d7-ab14-04d8549c1d05"
    $Environment = "AzureCloud"
    $Location = "West US"
}
elseif($SubscriptionName.Equals("OSTC Shanghai PM"))
{
    $SubscriptionID = "39558243-e960-4603-b1b4-a1a3ac08ed5b"
    $Environment = "AzureChinaCloud"
    $Location = "China East"
}
else
{
    Write-Host "Error: the subscription name is not exist,pls check and retry it" -ForegroundColor Red
    return;
}


<#
 config subscription
#>
Function SetSubscription ($SubscriptionID, $SubscriptionName, $Certificate, $storageAccount, $Environment, $Location)
{
    #echo "************************************************************************" >> $logfile
    #echo "Environment: $Environment" >> $logfile
    #echo "************************************************************************" >> $logfile
    Set-AzureSubscription -SubscriptionName $SubscriptionName -Certificate $Certificate -SubscriptionID $SubscriptionID -Environment $Environment
    Select-AzureSubscription -Current $SubscriptionName
    Write-Host "INFO: creating Storage Account" -ForegroundColor Green
    New-AzureStorageAccount -StorageAccountName $storageAccount -Location $Location
    if(!$?)
    {
        exit
    }
    Set-AzureSubscription –SubscriptionName $SubscriptionName –CurrentStorageAccountName $storageAccount
}


<#
 create VM
#>
Function CreateAzureVM ($ServiceName, $VmName, $ImageName, $VmSize, $UserName, $Passwd)
{
    
    New-AzureVMConfig -Name $VmName -InstanceSize $VmSize -ImageName $ImageName|
    Add-AzureProvisioningConfig -Linux -LinuxUser $UserName -Password $Passwd|
    New-AzureVM -ServiceName $ServiceName 
    if($?)
    {
        return $true
    }
    else
    {
        return $false
    }
    
}


<#
 check WALA version
#>
Function CheckWalaVersion($ServiceName, $VmName, $Command, $DistroName, $PublishedDate)
{
    $VmInfo = Get-AzureVM -ServiceName $ServiceName -Name $VmName | Get-AzureEndpoint

    if($VmInfo)
    {
        Write-Host "INFO: waiting for completing VM provisioning" -ForegroundColor Green
        while(!(Get-AzureVM -ServiceName $ServiceName -Name $VmName).InstanceStatus.Equals("ReadyRole"))
        {
            sleep(10)
        }
        Write-Host "INFO: getting WALA version..." -ForegroundColor Green
        $j = 0
        while($true)
        {
            sleep(5)
            $WalaVerInfo = (echo Y | .\tools\plink.exe -t -pw $Passwd -P $VmInfo.Port $UserName@($VmInfo.Vip) $Command)
            $info = [string]$WalaVerInfo
            if((++$j) -ge 3)
            {
                Write-Host "Error:Plink retry times out,please check connection available" -ForegroundColor Red
                break
            } 
            if(!$info)
            {
                Write-Host "INFO: retry to get WALA version..." -ForegroundColor Green                                  
                continue
            }
            if($info.ToLower().Contains("walinuxagent"))
            {
                break
            }               
        }
            
        if($j -ge 3)
        {
            echo "------------------------------------------------------------------------" >> $logfile
            echo "$DistroName : Plink connection times out,fail to get wala version " >> $logfile                  
            return $false
        }
            
        Write-Host "INFO: Successfully get the wala version: $WalaVerInfo" -ForegroundColor Green
        if($WalaVerInfo.Count -eq 2)
        {
            $WalaVersion = $WalaVerInfo[0]
            $DistroVersion = $WalaVerInfo[1]
            echo "------------------------------------------------------------------------" >> $logfile
            echo "Distro       : $DistroName" >> $logfile
            echo "PublishedDate: $PublishedDate" >> $logfile 
            echo "WALA version : $WalaVersion" >> $logfile
            echo "Distro Ver   : $DistroVersion" >> $logfile 
        }
        else
        {
            echo "------------------------------------------------------------------------" >> $logfile
            echo "Distro       : $DistroName" >> $logfile
            echo "PublishedDate: $PublishedDate" >> $logfile 
            echo "WALA Version : $WalaVerInfo" >> $logfile        
        }      
        Write-Host "INFO: the version info have been recorded to the file $logfile successful" -ForegroundColor Green
        return $true   
    }
    else
    {
        return $false
    }
}

Function DeleteService($ServiceName)
{
    if(Test-AzureName -Service $ServiceName)
    {
        
        Write-Host "INFO: remove the created Service: $ServiceName" -ForegroundColor Green
        Remove-AzureService -ServiceName $ServiceName -Force -DeleteAll
        Write-Host "INFO: Delete service ""$ServiceName"" successful" -ForegroundColor Green
    }
}

<#
 clean test environment
#>
Function CleanTestEnv($StorageAccount)
{
    if(Test-AzureName -Storage $StorageAccount)
    {
        Write-Host "INFO: Clear the test environment..." -ForegroundColor Green
        Write-Host "INFO: remove the created Storage Account" -ForegroundColor Green
        sleep(120)
        Remove-AzureStorageAccount -StorageAccountName $StorageAccount
        if($?)
        {
            Write-Host "INFO: Delete storage account ""$StorageAccount"" successful" -ForegroundColor Green
        }
    }
    
    Write-Host "INFO: Clean complete!" -ForegroundColor Green
}



<#
test steps
step 1: set subscription and create service
step 2: get latest image and create VM
step 3: get wala version info
step 4: clean test environment
#>
#$StorAccount = "ciwestus"
#Set-AzureSubscription -SubscriptionName $SubscriptionName -Certificate $Cert -SubscriptionID $SubscriptionID -Environment $Environment -CurrentStorageAccountName $StorAccount
#Select-AzureSubscription -Current $SubscriptionName
SetSubscription -SubscriptionID $SubscriptionID -SubscriptionName $SubscriptionName -Certificate $Cert -storageAccount $StorAccount -Environment $Environment -Location $Location
$logfile = ".\log\WalaVersion-"+$Environment+"-"+(Get-Date -Format MM-dd-HH-mm-ss)+".log"
for($i=0;$i -lt $ImageArray.Length;$i++)
{
    $DistroName = $ImageArray[$i]
    Write-Host "INFO: get the latest image for Distro: $DistroName" -ForegroundColor Green
    if($DistroName.Contains("Ubuntu"))
    {
        $ImageList = Get-AzureVMImage | where {$_.Label.Contains($DistroName)} | sort PublishedDate -Descending
    }
    else
    {
        $ImageList = Get-AzureVMImage | where {$_.Label.Equals($DistroName)} | sort PublishedDate -Descending
    }              
    if(!$ImageList)
    {
        Write-Host "Error: The image for Distro:""$DistroName"" do not exist" -ForegroundColor Red
        echo "------------------------------------------------------------------------" >> $logfile
        echo "$DistroName : The image do not exist " >> $logfile
        continue
    }
    $TimeStamp = Get-Date -Format MM-dd-HH-mm-ss
    $ServiceName = "ICA-WalaVersionCheck-" + $TimeStamp
    Write-Host "INFO: create a service: $ServiceName" -ForegroundColor Green
    New-AzureService -ServiceName $ServiceName -Location $Location
    $PublishedDate = $ImageList[0].PublishedDate
    $ImageLabel = $ImageList[0].Label
    $ImageName = $ImageList[0].ImageName
    $VmName = "ICA-VersionCheckVM-" + $TimeStamp
    Write-Host "INFO: create VM for Distro: $DistroName" -ForegroundColor Green
    #$ImageName = "andyleirhel66"
    $output = CreateAzureVM -ServiceName $ServiceName -VmName $VmName -ImageName $ImageName -VmSize $VmSize -UserName $UserName -Passwd $Passwd 
    if(!$output)
    {
        Write-Host "Error: Failed to creat VM" -ForegroundColor Red
        echo "------------------------------------------------------------------------" >> $logfile
        echo "$DistroName : Failed to creat VM " >> $logfile
        DeleteService -ServiceName $ServiceName                
        continue
    }
# the path of waagent is different between CoreOS and others
    if($DistroName.Contains("CoreOS"))
    {
        $cmd = '/usr/share/oem/python/bin/python /usr/share/oem/bin/waagent -version;uname -r'
    }
    else
    {
        $cmd = '/usr/sbin/waagent -version;uname -r'
    }
    $out = CheckWalaVersion -ServiceName $ServiceName -VmName $VmName -Command $cmd -DistroName $DistroName -PublishedDate $PublishedDate
    if(!$out)
    {
        Write-Host "Error: Failed to get wala version for Distro: ""$DistroName""" -ForegroundColor Red
        echo "------------------------------------------------------------------------" >> $logfile
        echo "$DistroName  : Failed to get wala version" >> $logfile
    }
    DeleteService -ServiceName $ServiceName
}

CleanTestEnv -StorageAccount $StorAccount






