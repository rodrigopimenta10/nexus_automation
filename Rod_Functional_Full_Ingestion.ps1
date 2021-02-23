<#
  .SYNOPSIS

    You pass in the destination path to the directory with the deliveries to ingest as a parameter. It zips and ingests all the software components in that directory.

  .DESCRIPTION

    # ./Rod_Functional_Full_Ingestion.psl -deliveryFolderPath 'C:\Users\zk787uq\Desktop\Ingestion_Formatted' -verbose_logging
    # ./ Rod_Functional_Full_Ingestion_v2.psl -deliveryFolderPath 'E:\Ingestion_Formatted' -verbose_logging

    Jenkins Job: https://wva60bhhzpjk00v/view/Win10_Deliveries/job/Win10_Deliveries_MQAgent/

    Edge cases that do not easily fall into an ingestion case category and are a bit 'hard-coded' for now:
    'Microsoft Visual C++ Runtime x86 2017 - 14.14.26429.4 
    'Microsoft Visual C++ Runtime x64 2017 - 14.14.26429.4'

    Errors we throw which we commented out for now in order to continue iteration:
    None

  .PARAMETER $deliveryFolderPath
  
    Path to the delivery directory root folder.
  
  .PARAMETER verbose_logging
    
    Toggle this switch to initiate verbose logging.
#>

param (
    [Parameter(Mandatory=$false)][string]$deliveryFolderPath = "C:\Users\zk787uq\Desktop\Ingest_Edge",
    [Parameter(Mandatory=$false)][switch]$verbose_logging
    )

· "$PSScriptRoot\Get-FolderItem.ps1"

$application_user = $( whoami ) 
$computer_name = $( hostname ) 
$current_drive = (get-location).Drive.Name + ":\"
$full_cache_folder = $current_drive + $cacheFolder 
$runtime_alerts = @{ }
$alert_to_collect = 'ERROR', 'WARN', 'FATAL'
$global:progressPreference = 'silentlycontinue'

$vendor_alias = @{ } 
$vendor_alias.add('NCR', 'ncr') 
$vendor_alias.add('DBD', 'diebold') 
$vendor_alias.add('DN', 'diebold') 
$vendor_alias.add('NHA', 'nha')
$vendor_alias.add('PHX', 'phoenix')

$vendor_alias.add('Avecto', 'avecto')
$vendor_alias.add('Bank of America', 'bank_of_america')
$vendor_alias.add('Greyware', 'greyware') 
$vendor_alias.add('IBM', 'ibm') 
$vendor_alias.add('McAfee', 'mcafee') 
$vendor_alias.add('Microsoft', 'microsoft') 
$vendor_alias.add('Splunk', 'splunk')


function run_log_print([string]$log_message, [string]$log_level, [string]$return_code)
{
    $log_date_time = $( get-date -Format "MM-dd-yyyy HH:mm:ss.fff" )
    if (($log_level -eq "DEBUG") -and ($verbose_logging))
    {
        Write-Output "$log_date_time $log_level $computer_name $application_user $return_code $log_message"
    }
    elseif ($log_level -ne "DEBUG")
    {
        Write-Output "$log_date_time $log_level $computer_name $application_user $return_code $log_message"
        if ($log_level -in $alert_to_collect)
        {
            $runtime_alerts.add($log_date_time, ($log_level, $log_message))
        }
    }
}

function reivew_configuration_details
{
    run_log_print -log_message "Review of Configuration Deails: " -log_level "INFO" -return_code "0"
    Get-Variable | Out-String
}
#####################################################################
#
# Functions for story
#
#####################################################################

function Get-MsiDatabaseVersion {
    param (
        [string] $fn
    )

    try {
        $FullPath = (Resolve-Path $fn).Path
        $windowsInstaller = New-Object -com WindowsInstaller.Installer

        $database = $windowsInstaller.GetType().InvokeMember(
                "OpenDatabase", "InvokeMethod", $Null, $windowsInstaller, @($FullPath, 0)
                )
        
        $q = "SELECT Value FROM Property WHERE Property = 'ProductVersion'"
        $View = $database.GetType().InvokeMember(
                "OpenView", "InvokeMethod", $Null, $database, ($q)
                )

        $View.GetType().InvokeMember("Execute", "InvokeMethod", $Null, $View, $Null)

        $record = $View.GetType().InvokeMember(
                "Fetch", "InvokeMethod", $Null, $View, $Null
                )
        $productVersion = $record.GetType().InvokeMember(
                "StringData", "GetProperty", $Null, $record, 1
                )
    
        $View.GetType().InvokeMember("Close", "InvokeMethod", $Null, $View, $Null)

        return $productVersion
    } catch {
        #throw error with current object
        throw "Failed to get MSI file version the error was: {0}." -f $_
    }
}

##########################################################################################
#
# The first function called inside of the 'componentsIngestion' function (the only function called inside of the main driver).
#
##########################################################################################

function checkifURLISAvailable ([string]$downloadUrl) 
{
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $HTTP_Request = [System.Net.WebRequest]::Create($downloadUrl)
    # We then get a response from the site. 
    try{
        $HTTP_Response = $HTTP_Request.GetResponse() 
        # We then get the HTTP code as an intege.
        $HTTP_Status = [int]$HTTP_Response.StatusCode
        
        #If we get an HTTP status of 200, it is a success, otherwise it is a failure.
        If ($HTTP_Status -eq 200) {
            $HTTP_Response.Close()
            return $true
        }
        Else {
            $HTTP_Response.Close() 
            return $false
        }
    }
    catch{
        Write-Output "Sorry we cannot connect to $downloadUrl URL." 
        #Write-Output "$($_.Exception.InnerException)"
    }
}

function UpdateLastModDate ([String]$zipdestination)
{
    try
    {
        [System.DateTime] $dateTime = New-Object System.DateTime (1980, 07, 01, 00, 00, 00, 000, [System.DateTimeKind]::Utc)
        [System.IO.Compression.ZipArchive] $zipArc = [io.compression.zipfile]::Open($zipdestination, [System.io.compression.ZipArchiveMode]::Update)
        foreach($entry in $zipArc.Entries) {
            ([System.IO.Compression.ZipArchiveEntry] $entry).LastWriteTime = $dateTime
        }
    }
    finally{
        if ($zipArc -ne $null) {
            $zipArc.Dispose()
        }
    }
}

function zipcomponent([string] $compSourcePath, $compSourceNaming, $version)
{
    Write-Host "Hook 4.6.1, zipcomponent function"
    Write-Host $compSourcePath
    $zipdestination = "$compSourceNaming-$version.zip"
    Write-Host $zipdestination
    #$zipdestination = "C:\Users\zk787uq\Desktop\testing-10.0.0.zip"
    #$compSourcePath = "C:\Users\zk787uq\Desktop\testing"
    If(Test-path $zipdestination) {Remove-item $zipdestination -Force}
    Add-Type -assembly "system.io.compression.filesystem"
    $compressionLevel = [System.IO.Compression.CompressionLevel]::Optimal
    [io.compression.zipfile]::CreateFromDirectory($compSourcePath, $zipdestination, $compressionLevel, $true)
    UpdateLastModDate ($zipdestination)

    Write-Host "Hook 4.6.2, zipped folder dropped into the current delivery folder"
    <# 
    $sourceFolder = "C:\Users\zk787uq\Desktop\testing"
    $destinationZip = "C:\Users\zk787uq\Desktop\testing.zip"
    [Reflection.Assembly]::LoadWithPartialName( "System.IO.Compression.FileSystem" )
    [System.IO.Compression.ZipFile]::CreateFromDirectory($sourceFolder, $destinationzip)
    #>

    return $zipdestination
}

function CreateStringContent()
{
    # We take in four string parameters, (name, value, fileName, mediaTypeHeaderValue).
    # We only call this function with two parameters, and one time with one parameter. The time we call it with only one parameter would give us an error as this function requires at least two mandatory parameters.
    param
    (
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Name, # "r", "g", "a", "v", "p"
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Value, # $Repository, $Group, $Artifact, $Version, $Packaging, $PackagePath
        [string]$FileName,
        [string]$MediaTypeHeaderValue
    )
    
    #We create a System.Net.Http object, and assign the $Name value to the .Name field in its reflection to the object.
    $contentDispositionHeaderValue = New-Object -TypeName System.Net.Http.Headers.ContentDispositionHeaderValue -ArgumentList @("form-data")
    $contentDispositionHeadervalue.Name = $Name
    
    
    if ($FileName)
    {
        #If we are given a fileName parameter (which we never do use), we give that value to the $contentDispositionHeaderValue object's 'FileName' field.
        $contentDispositionHeaderValue.FileName = $FileName
    }
    
    #Finally we create a System.Net.Http object for $content. We give the $Value parameter string to its argument list.
    #Then we give the $contentDispositionHeaderValue object (object with the $Name parameter value ("r", "g", "a", "v", "p")) to the content.Headers.ContentDisposition field.
    $content = New-Object -TypeName System.Net.Http.StringContent -ArgumentList @($Value)
    $content.Headers.ContentDisposition = $contentDispositionHeadervalue

    if ($MediaTypeHeaderValue)
    {
        #If we are given a MediaTypeHeaderValue parameter (which we never do use), we give it to the appropriate field in $content.
        $content.Headers.ContentType = New-Object -TypeName System.Net.Http.Headers.MediaTypeHeaderValue $MediaTypeHeaderValue
    }

    #return $content object, which holds data for both the parameter $Name and $Value.
    return $content
}

function CreateStreamContent()
{
    param
    (
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$PackagePath
    )
    
    $packageFileStream = New-Object -TypeName System.IO.FileStream -ArgumentList @($PackagePath, [System.IO.FileMode]::Open)
    
    $contentDispositionHeaderValue = New-Object -TypeName System.Net.Http.Headers.ContentDispositionHeaderValue "form-data"
    $contentDispositionHeaderValue.Name = "file"
    $contentDispositionHeaderValue.FileName = Split-Path $packagePath -leaf

    $streamContent = New-Object -TypeName System.Net.Http.StreamContent $packageFileStream
    $streamContent.Headers.ContentDisposition = $contentDispositionHeadervalue
    $streamcontent.Headers.ContentType = New-Object -TypeName System.Net.Http.Headers.MediaTypeHeaderValue "application/octet-stream"
    
    return $streamContent
}

function GetHttpClientHandler()
{
    param
    (
        [System.Management.Automation.PSCredential][parameter(Mandatory = $true)]$Credential
    )
    
    $networkCredential = New-Object -TypeName System.Net.NetworkCredential -ArgumentList @($Credential.UserName, $Credential.Password)
    $httpClientHandler = New-Object -TypeName System.Net.Http.HttpClientHandler
    $httpClientHandler.Credentials = $networkCredential

    return $httpClientHandler
}

##################################################Split between main ingestion functions below and auxiliary helper functions above#####################################

function PostArtifact()
{
    param
    (
        # We take in 3 parameters, the ($EndpointUrl, $Handler with the credentials, and $Content)
        [string][parameter(Mandatory = $true)]$EndpointUrl,
        [System.Net.Http.HttpClientHandler][parameter(Mandatory = $true)]$Handler,
        [System.Net.Http.HttpContent][parameter(Mandatory = $true)]$Content
    )

    Write-Host "Hook 4.11.1.6.1, inside 'PostArtifact' function."
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    #We feed in the $Handler to the initialization of the new object to get back the appropriate object.
    $httpClient = New-Object -TypeName System.Net.Http.Httpclient $Handler

    Write-Host "Hook 4.11.1.6.2"
    try
    {
        Write-Host "Hook 4.11.1.6.3, before PostAsync command"
        Write-Host "Command = ($httpClient.PostAsync(""$EndpointUrl/service/local/artifact/maven/content"", $Content)).Result"
        Write-host "httpClient: $httpClient, EndpointUrl: $EndpointUrl, Content: $Content"
        Write-Host "Make sure you are running this on Jenkins with Jenkins service account credentials in order to be able to upload"
        #EndpointUrl =
        #We use the $httpClient object (which contains our $credentials), to call PostAsync with the '$uploadURL/service/local/artifact/maven/content'. We get the .Result field of the object returned here.
        $response = ($httpClient.PostAsync("$EndpointUrl/service/local/artifact/maven/content", $Content)).Result
        
        $temp = $response.IsSuccessStatusCode
        Write-Host "Hook 4.11.1.6.4, after PostAsync command"
        Write-Host "Response from PostAsync command: $response, also the success code of the response: $temp"
        #If the $response from the .PostAsync POST request is not a success HTTP status code, error.
        if (!$response.IsSuccessStatusCode)
        {
            Write-Host "The response has an unsuccessful response code, throw error"
            $responseBody = $response.Content.ReadAsStringAsync().Result
            $errorMessage = "Status code {0}. Reason {1}. Server reported the following message: {2}." -f $response.StatusCode, $response.ReasonPhrase, $responseBody
            throw [System.Net.Http.HttpRequestException] $errorMessage
        } else {
            Write-Host "The response has a successful response code"
        }
        #return $response.Content.ReadAsStringAsync().Result #Apparently we don't need a return value for this function.
    }
    #No catch block for this try block above for the .PostAsync POST request, but a finally block which always runs. This is to clear the $httpClient object and $reponse object if either is not $null.
    finally
    {
        if($null -ne $httpClient)
        {
            $httpClient.Dispose()
        }

        if($null -ne $response)
        {
            $response.Dispose()
        }
    }
}

function UploadComponentToNexus()
{
    #We are given the $EndpointURL, 6 parameters needed to form the appropriate object we will send, and the credential.
    [CmdletBinding()] 
    param
    (
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$EndpointUrl, #uploadURL
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Repository, # Defined as 'VendorDeliveris10'
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Group, #"com." + $vendor + ".atm"
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Artifact, #Name of the parent folder of the current msi file in the iteration.
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Version, #Should be the version number associated with the current msi file in the iteration, but is never defined so is always an empty variable.
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$Packaging, #"zip"
        [string][parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]$PackagePath, #$zipLocation, the path of the locally zipped component (msi file) in the current iteration, returned from the 'zipcomponent' function.
        [System.Management.Automation.PSCredential][parameter(Mandatory = $true)]$Credential #That credentials object with the current environment's username and password.
    )
    BEGIN
    {
        Write-Host "Hook 4.11.1.1"
        #Case 1: If the $ziplocation (path of the locally zipped component (msi file) in the current iteration), returned from the 'zipcomponent' function, is an empty string.
        if (-not (Test-Path $PackagePath))
        {
            $errorMessage = ("Package file {0} missing or unable to read." -f $PackagePath)
            $exception = New-Object System.Exception $errorMessage
            $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, 'XLDPkgUpload', ([System.Management.Automation.ErrorCategory]::InvalidArgument), $packagePath
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
        #We define a .NET core class (System.Net.Http) in our current powershell session.
        
        Add-Type -AssemblyName System.Net.Http
    }
    PROCESS
    {
        Write-Host "Hook 4.11.1.2"
        #We use these 6 parameters to feed into the 'CreateStringContent' function and get back the appropriate object.
        $repoContent = CreateStringContent "r" $Repository
        $groupContent = CreateStringContent "g" $Group

        $artifactContent = CreateStringcontent "a" $Artifact
        $versionContent = CreateStringContent "v" $Version
        $packagingContent = CreateStringContent "p" $Packaging
        Write-Host "Hook 4.11.1.3"
        $streamContent = CreateStreamContent $PackagePath #Calls 'CreateStreamContent' instead of 'CreateStringContent' function.
        Write-Host "Hook 4.11.1.4"

        #We create a (System.Net.Http.MultipartFormDataContent) object and add all of the 6 objects we created above to it.
        $content = New-Object -TypeName System.Net.Http.MultipartFormDataContent
        $content.Add($repoContent)
        $content.Add($groupContent)
        $content.Add($artifactContent)
        $content.Add($versionContent)
        $content.Add($packagingContent)
        $content.Add($streamContent)

        Write-Host "Hook 4.11.1.5"
        #We send the $Credential object to this function in order to get back the appropriate object we must use for the 'PostArtifact' function.
        $httpClientHandler = GetHttpClientHandler $Credential

        Write-Host "Hook 4.11.1.6"
        # The 'PostArtifact' function is where we do the actual POST request and upload to NEXUS. We feed it 3 parameters: $uploadURL, $httpClientHandler ($credentials object), and the $content object holding all the 6 object fields we created above.
        PostArtifact $EndpointUrl $httpClientHandler $content
        #return PostArtifact $Endpointurl $httpClientHandler $content
        Write-Host "Hook 4.11.1.7"
    }
    end { }
}

function ingestComp_XML($uploadURL, $group, $artifact, $version, $ziplocation, $credentials)
{
    Write-Host "Hook 4.11.1"
    $packaging = "zip"
    UploadComponentToNexus $uploadURL "VendorDeliveries10" $group $artifact $version $packaging $zipLocation $credentials
}

##########################################################################
#
# This is the only function called inside of our Main Driver for this script. It is our main ingestion function. 
# It takes three parameters, the current delivery directory in the current foreach loop itertation inside of the main driver, 
# and the credentials object containing the current environment's username and the current environment's password, and the 
# $componentSourceDict of the current delivery in the current iteration. 
# This function has two key functions inside of it: 'zipcomponent' and 'ingestcomp_XML'
#
########################################################################## 
function componentsIngestion($rootFolderName, [System.Management.Automation.PSCredential]$credentials, $componentSourceArr)
{
    $uploadURL = "https://ah-1005376-001.sdi.corp.bankofamerica.com:8082/nexus"
    $downloadUrl = "https://ah-1005376-001.sdi.corp.bankofamerica.com:8082/nexus/content/repositories/VendorDeliveries10"

    Write-Host "Hook 4.1"

    #rootFolderName is the full path of the current delivery category directory in the iteration of the loop in the Main Driver,
    #We get the leaf to just have the name of the delivery category directory.
    $deliveryCategoryFolderName = Split-Path $rootFolderName -Leaf

    Write-Host "Hook 4.2"
    
    #We call the 'checkifURLIsAvailable' function with the $uploadURL string to check if the $uploadURL URL is available.
    $canbeConnected = checkifURLIsAvailable($uploadURL)
    if ($verbose_logging) { reivew_configuration_details }
    
    Write-Host "Hook 4.3"

    #Case 1: If we could not get a HTTP response of '200' from the $uploadURL url, error. 
    if(-Not ($canbeConnected)) {
        Write-Output "[Error] We cannot connect to Nexus Repository at this time. Please try the ingestion process later"
        return
    }

    #We create two arrays which will be used to collect information later. 
    $componentsUploaded = @()
    $componentsNotUploaded = @()

    #We create an array which will be used to collect all the $zipLocation path locations returned from the zip function.
    $leftoverZipsToRemove = @()

    #We set $errocc to $false.
    $erroccFlag=$false

    Write-Host "Hook 4.4"

    #We now loop through all the software component directories inside of the current delivery category directory.
    foreach($softCompDir in $componentSourceArr) {
        Write-Host "Hook 4.4 Start of new software component iteration."
        [string]$parentFolder = ""
        $installer_vendor = ""




        $parentFolder = $softCompDir.Name #This is the name of the current parent directory.
        #$rootFolderName is the full path of the current delivery category directory in the iteration of the loop in the Main Driver.
        Write-Host $parentFolder

        $noVersionFlagger = $false

        if (($parentFolder -split '(^.*)\s\d*\.\d*.*')[1] -eq $null)
        {
            Write-Host "$parentFolder lacks a version number. It will be given the version number of 10.10 for now, for testing purposes."
            $noVersionFlagger = $true
            #throw "'${parentFolder}' lacks a version number."
            #break
        }

        if (($parentFolder -split '(^.*_.*\s\d*\.\d*.*)')[1]) #Three Main Vendors
        {
            run_log_print -log_message "Regex Vendor[Underscore] Pattern Found:$parent Folder" -log_level DEBUG
            $installer_vendor = ($parentFolder -split '([^_]+)')[1]
            run_log_print -log_message "Vendor=$installer_vendor" -log_level DEBUG
            $installer_application = ($parentFolder -split '(^.*)\s\d*\.\d*.*')[1]
            run_log_print -log_message "Application_Name=$installer_application" -log_level DEBUG
        }
        elseif (($parentFolder -split '(^Bank of America\s.*\s\d*\.\d*.*)')[1]) #Bank of America
        {
            run_log_print -log_message "Regex Bank of America Pattern Found:$parentFolder" -log_level DEBUG
            $installer_vendor = ($parentFolder -split '^(Bank of America).*')[1]
            run_log_print -log_message "Vendor=$installer_vendor" -log_level DEBUG
            $installer_application = ($parentFolder -split '(Bank of America\s.*)\s\d*\.\d*.*')[1]
            run_log_print -log_message "Application_name=$installer_application" -log_level DEBUG
        }
        elseif (($parentFolder -split '(^.*\s.*\s\d*\.\d*.*)')[1]) #Third party components
        {
            #C:\Users\zk787uq\Bitbucket\server_scripts\ATMCICD-223\Rod_Functional_Full_Ingestion.psl 'C:\Users\zk787uq\Desktop\Ingest_Edge' -verbose_logging
            Write-Host "We hit the third party components regex case"
            Write-Host "parentFolder is: $parentFolder"
            #There is currently one edge case for this overlying case: 'Microsoft Visual C++ Runtime x86 2017 - 14.14.26429.4'. There is note of all current edge cases in script's get-help description.
            #$a = ($parentFolder -eq "Microsoft Visual C++ Runtime x86 2017 - 14.14.26429.4")
            if ($parentFolder -eq "Microsoft Visual C++ Runtime x86 2017 - 14.14.26429.4")
            {
                Write-Host "We hit the 'Microsoft Visual C++ Runtime x86 2017 - 14.14. 26429.4' edge case"
                run_log_print -log_message "Regex Vendor[Space] Pattern Found:$parentFolder" -log_level DEBUG
                $installer_vendor = ($parentFolder -split '([^\s]+)')[1]
                run_log_print -log_message "Vendor=$installer_vendor" -log_level DEBUG
                $installer_application = "Microsoft Visual Cplusplus Runtime x86 2017"
                Write-Host "installer application: $installer_application"
                run_log_print -log_message "Application_name=$installer_application" -log_level DEBUG
            } 
            elseif ($parentFolder -eq "Microsoft Visual C++ Runtime x64 2017 - 14.14.26429.4") 
            {
                Write-Host "We hit the 'Microsoft Visual C++ Runtime x64 2017 - 14.14.26429.4' edge case"
                run_log_print -log_message "Regex Vendor [Space] Pattern Found:$parentF older" -log_level DEBUG
                $installer_vendor = ($parentFolder -split '([^\s]+)')[1]
                run_log_print -log_message "Vendor=$installer_vendor" -log_level DEBUG
                $installer_application = "Microsoft Visual Cplusplus Runtime x64 2017"
                Write-Host "installer application: $installer_application"
                run_log_print -log_message "Application_Name=$installer_application" -log_level DEBUG
            } 
            else
            {
                Write-host "We hit the common case for third party"
                #Common case
                run_log_print -log_message "Regex Vendor[Space] Pattern Found:$parentFolder" -log_level DEBUG
                $installer_vendor = ($parentFolder -split '([^\s]+)')[1]
                run_log_print -log_message "Vendor=$installer_vendor" -log_level DEBUG
                $installer_application = ($parentFolder -split '(^\w+\s.*)\s\d*\.\d*.*')[1]
                run_log_print -log_message "Application_name=$installer_application" -log_level DEBUG
            }
        }
        else
        {
            Write-Host "$parentFolder lacks a vendor Pattern. The 'installer_application' name given to be associated with this component will be its normal 'parentFolder' name: $parentFolder"

            #Create case if it is a software component which starts with 'Microsoft Visual C++ Runtime'. We need to replace the 'C++' with 'Cplusplus'.
            #$a = (("Microsoft Visual C++ Runtime x64 2010 Update 1" -split '(^. *\s.*\ sid*\.\d*.*)') [1]) = $null. It doesn't fall into the 'Third party components' category

            #$a = ("Microsoft Visual C++ Runtime x64 2010 Update 1".substring(0,28) -e q "Microsoft Visual C++ Runtime") = True
            if ($parentFolder.substring(0,28) -eq "Microsoft Visual C++ Runtime")
            {
                #$a = "Microsoft Visual C++ Runtime x64 2010 Update 1".replace("+", "plus")
                $installer_application = $parentFolder.replace("+", "plus")
            }
            else
            {
                #For other software components without a vendor pattern, just feed the normal $parentFolder name as the installer_application name.
                $installer_application = $parentFolder
            }
            #throw "'${parentFolder}' lacks a vendor Pattern."
            #break
        }
        #Replace the spaces in $installer_application with underscores so it is to convention for ingestion.
        $installer_application = $installer_application.replace(" ", "_")
        Write-Host "Past regex" 
        Write-Host $installer_application
        $parsedParentFolderPathNoVersion = $rootFolderName + "\" + $installer_application
        $currSoftCompFulldir = $softCompDir.FullName
        Write-Host $parsedParentFolderPathNoVersion 
        Write-Host "Hook 4.5"

        #If we got a success code from our test connection function. 
        if($canbeConnected)
        {
            try{
                Write-Host "Hook 4.6" 
                Write-Host $deliveryCategoryFolderName
                $vendor = ""
                $vendor = $vendor_alias[$deliveryCategoryFolderName] #Bank of America -> bank_of america. To the conventions of how we ingest the Bank of America components into NEXUS.

                Write-Host $vendor

                #[string] $zipval = $softCompDir.FullName #This is the full path of th e parent directory of the current msi file. Value: C:\Users\zk787uq\Desktop\Ingestion_Testing\10.0.0_McAfee\McAfee ENS 10.6.1
                [string] $zipVal = $parsedParentFolderPathnoVersion

                Write-Host $zipVal

                #We have zipVal, now we just need version to use our zip function.
                #We set a default version of '10.10.10', we get the version using regex on the software component directory's name.

                $installer_version = "10.10"

                if (!$noVersionFlagger){ 
                    if ($installer_application -eq "Bank_of_America_.Net_DLL"){
                        $installer_version = "3.0.1.0"
                    } elseif ($installer_application -eq "Bank_of_America_Enable_TLSv1.2_Only") {
                        $installer_version = "1.0"
                    } else {
                        $installer_version = ($parentFolder -split '(\d*\.\d*.*)')[1] # ("McAfee ENS 10.6.1" -split 'l\d+T. \d*.*)')[1] = 10.6.1
                    }
                }

                <#I decided against using the get-msi-version function on the msi I would find as this wouldnt be to standard if it didnt match the version in the name and therefore we shouldnt be running it with this code.
                #Then, we get an array of just the msi files inside of the current software component directory in the iteration.
                #If the array is not empty (-lt 1), then there is at least one msi file:
                #We get the first msi file in the array's, version using our get-msi-version function. We will account for the case when we need to get other versions as well later.
                
                
                
                
                
                
                
                
                #>

                


