<#
  .SYNOPSIS
    You can feed this script a task sequece ts.xml (in this case it's the Serenity TS) and it parses all the software 
    components the task sequence uses. Then the script pulls down from NEXUS the software components which
    are required by the task sequence, if it is not already in the cache, to the cached location.
    
    Finally, the script unpacks the software component to the 'Applications' folder of the deployment share if that
    switch is turned on.

  .DESCRIPTION
    
    Example: 
        Local testing:
            cd C:\Users\zk787uq\Desktop\testing
            ./component_retrieval.psl -mdt_build_tasklist "./ts.xml" -local_destination "C:\Users\zk787uq\Desktop\testing\Applications" -cacheFolder "VendorDeliveryCache" -verbose_logging

        Consideration:
            This script will be run on build server 123 (specifically on the D:\ drive) through a Jenkins job.
        
            cd E:\testing_1
            ./component_retrieval.psl -mdt_build_tasklist "./ts.xml" -local_destination "E:\Windows_10testing\Applications" -cacheFolder "VendorDeliveryCacheTesting" -verbose_logging

        Jenkins:
            cd ATMCICD-206
            ./component_retrieval.psl -mdt_build_tasklist "./ts.xml" -local_destination "E:\Windows_10testing\Applications" -cacheFolder "VendorDeliveryCacheTesting" -unpackToDeploymentShare -verbose_logging
        
        We take four optional parameters.

  .PARAMETER $mdt_build_tasklist
    
    The path to the XML file to parse and extract all the software component elements information inside.

  .PARAMETER $local_destination

  .PARAMETER $cacheFolder
    
    The name of the folder you would like to create in the current drive (the drive this script is run on) to be your
    cache folder.

  .PARAMETER $verbose_logging
#>

param (
    [Parameter(Mandatory = $false)][string]$mdt_build_tasklist = "ts.xml",
    [Parameter(Mandatory = $false)][string]$local_destination = "C:\Users\zk787uq\Desktop\testingTwo\Applications",
    [Parameter(Mandatory = $false)][string]$cacheFolder = "VendorDeliveryCache", 
    [Parameter(Mandatory = $false)][switch]$verbose_logging
    )

$Logfile = "C:\Users\ze787uq\Desktop\testingTwo"

$application_user = $( whoami ) 
$computer_name = $( hostname )
$current_drive = (get-location).Drive.Name + ":\"
$full_cache_folder = $current_drive + $cacheFolder
$runtime_alerts = @{ } 
$alert_to_collect = 'ERROR', 'WARN', 'FATAL' 
$global:progressPreference = 'silentlyContinue'

$downloadUrl = "https://ah-1005376-001.sdi.corp.bankofamerica.com:8082/nexus/content/repositories/VendorDeliveries10"

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

Function LogWrite
{
    Param ([string]$logstring)
    #Add-content $Logfile -value $logstring
}

function run_log_print([string]$log_message, [string]$log_level, [string]$return_code)
{
    $log_date_time = $( get-date -Format "MM-dd-yyyy HH:mm:ss.fff" ) 
    if (($log_level -eq "DEBUG") -and ($verbose_logging))
    {
        Write-Output "$log_date_time $log_level $computer_name $application_user $return_code $log_message"
        LogWrite "$log_date_time $log_level $computer_name $application_user $return_code $log_message"
    }
    elseif ($log_level -ne "DEBUG")
    {
        Write-Output "$log_date_time $log_level $computer_name $application_user $return_code $log_message"
        LogWrite "$log_date_time $log_level $computer_name $application_user $return_code $log_message"
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

######################################################################################
#
# Functions for story
#
######################################################################################

function checkComponentInCache($cachedComponentZipLocation, $componentArtifactFileName)
{
    if (Test-Path "$cachedComponentZipLocation\$componentArtifactFileName")
    {
        return $true
    }
    return $false
}

function check_artifact_already_present($local_destination, $target_directory_name)
{
    if (Test-Path "$local_destination\$target_directory_name")
    {
        return $true
    }
    return $false
}

function checkifURLIsAvailable([string]$downloadUrl)
{
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 
    $HTTP_Request = [System.Net.WebRequest]::Create($downloadUrl)

    # We then get a response from the site. 
    try
    {
        $HTTP_Response = $HTTP_Request.GetResponse() 
        # We then get the HTTP code as an integer. 
        $HTTP_Status = [int]$HTTP_Response.StatusCode

        If ($HTTP_Status -eq 200)
        {
            $HTTP_Response.Close()
            return $true
        }
        Else
        {
            $HTTP_Response.Close() 
            return $false
        }
    }
    catch
    {
        Write-Output "Sorry we cannot connect to $downloadUrl URL." 
        #Write-Output "$($_.Exception.InnerException)"
    }
}

function retrieval_artifacts_from_artifact_store($artifact_info, $local_destination, $target_directoy_name)
{
    # We set this flag to true 
    $retrievalPassed = $true 
    # We check if we can connect (get a 200 HTTP response) from $downloadUrl 
    $canbeConnected = checkifURLISAvailable($downloadUrl) 
    if (-Not($canbeConnected))
    {
        #If we can not connect, throw error. 
        run_log_print -message "Cannot connect to: $downloadUrl." -log_level Error 
        $retrievalpassed = $false 
        exit 1
    }

    $installer_application = $artifact_info.vendor_application 
    $installer_version = $artifact_info.vendor_application_version 
    $installer_vendor = $artifact_info.vendor_name

    $installer_application = $installer_application.replace(" ", "_")

    # Finds Matching alias for Vendor through dictionary
    if ($vendor_alias[$installer_vendor])
    {
        $installer_vendor = $vendor_alias[$installer_vendor]
        run_log_print -log_message "Found Matching alias_for_Vendor=$installer_vendor" -log_level INFO
    }

    # We set the group appropriately. 
    $group = "com/" + $installer_vendor + "/atm"
    [string]$artifactFileName = $installer_application + "-" + $installer_version + ".zip"
    [String]$finalUrl = "$downloadUrl/$group/$installer_application/$installer_version/$artifactFileName"
    $cachedComponentZipLocation = "$full_cache_folder\$group\$installer_application\$installer_version"
    
    #We call the 'checkComponentInCache' function to see if this component is in cache.
    #We check the appropriate $cachedComponentZipLocation for the corresponding $artifactFileName
    $inCache = checkComponentInCache $cachedComponentZipLocation $artifactFileName 
    if (-Not($inCache))
    {
        #If it isn't in the appropriate cache we created, then we can download the artifact and put it in the cache location.
        run_log_print -log_message "$artifactFileName not found in Cache." -log_level INFO
        run_log_print -log_message "Downloading=$finalUrl" -log_level DEBUG
        download_artifact -finalURL $finalUrl -artifactFileName $artifactFileName -local_destination $local_destination -target_directoy_name $target_directoy_name -cachedComponentZipLocation $cachedComponentZipLocation
    }
    else
    {
        run_log_print -log_message "$artifactFileName found in Cache." -log_level INFO
        run_log_print -log_message "Unpacking=$artifactFileName Full_Directory=$local_destination\$target_directoy_name" -log_level INFO
        Expand-Archive -Path "$cachedComponentZiplocation\$artifactFileName" -DestinationPath $local_destination\$target_directoy_name -Force
    }
}

function download_artifact
{
    Param (
        [Parameter(Mandatory = $true)] $finalUrl, 
        [Parameter(Mandatory = $true)] $artifactFileName, 
        [Parameter(Mandatory = $false)] $local_destination = ".", #default 
        [Parameter(Mandatory = $false)][bool]$unpack = $true, # default 
        [Parameter(Mandatory = $true)] $target_directoy_name, 
        [Parameter(Mandatory = $true)] $cachedComponentZipLocation
    )

    run_log_print -log_message "local_destination=$local_destination artifactFileName=$artifactFileName" -log_level DEBUG
    try
    {
        New-Item -Path $cachedComponentZipLocation -ItemType Directory -Force | Out-Null
        Invoke-WebRequest -Uri $finalURL -OutFile $cachedComponentZipLocation\$artifactFileName
        if ($unpack)
        {
            run_log_print -log_message "Unpacking=$artifactFileName Full_Directory=$local_destination\$target_directoy_name" -log_level INFO
            Expand-Archive -Path $cachedComponentZipLocation\$artifactFileName -DestinationPath $1ocal_destination\$target_directoy_name -ErrorAction Stop | Out-Null
        }
    }
    catch
    {
        run_log_print -log_message "Unable to Download=$artifactFileName." -log_level WARN
    }
}

function validate_installer_pattern($installer_name)
{
    $Null = @(
    if (($installer_name -split '(^.*)\s\d*\.\d*.*')[1] -eq $null)
    {
        throw "'${installer_name}' lacks a version number." 
        break
    }
    #
    if (($installer_name -split '(^.*_*\s\d*\.\d*.*)')[1])
    {
        run_log_print -log_message "Regex Vendor[Underscore] Pattern Found:$installer_name" -log_level DEBUG
        $installer_vendor = ($installer_name -split '([^_]+)')[1] 
        run_log_print -log_message "Vendor=$installer_vendor" -log_level DEBUG 
        $installer_application = ($installer_name -split '(^.*)\s\d*\.\d*.*')[1]
        run_log_print -log_message "Application_Name=$installer_application" -log_level DEBUG
    }
    elseif (($installer_name -split '(^Bank of America\s.*\s\d*\.\d*.*)')[1])
    {
        run_log_print -log_message "Regex Bank of America Pattern Found:$installer_name" -log_level DEBUG
        $installer_vendor = ($installer_name -split '^(Bank of America).*')[1] 
        run_log_print -log_message "Vendor=$installer_vendor" -log_level DEBUG
        $installer_application = ($installer_name -split '(Bank of America\s.*)\s\d*\.\d*.*')[1]
        run_log_print -log_message "Application_name=$installer_application" -log_level DEBUG
    }
    elseif (($installer_name -split '(^.*\s.*\s\d*\.\d*.*)')[1])
    {
        run_log_print -log_message "Regex Vendor[Space] Pattern Found:$installer_name" -log_level DEBUG
        $installer_vendor = ($installer_name -split '([^\s]+)')[1] 
        run_log_print -log_message "Vendor=$installer_vendor" -log_level DEBUG 
        $installer_application = ($installer_name -split '(^\w+\s.*)\s\d*\.\d*.*')[1]
        run_log_print -log_message "Application_name=$installer_application" -log_level DEBUG
    }
    else
    {
        throw "'${installer_name}' lacks a vendor Pattern." 
        break
    }
    $vendor_application_version = ($installer_name -split '(\d*\.\d*.*)')[1] 
    run_log_print -log_message "Version=$vendor_application_version" -log_level DEBUG 
    $installer_info = @{ }
    $installer_info.add('vendor_name', $installer_vendor) 
    $installer_info.add('vendor_application', $installer_application) 
    $installer_info.add('vendor_application_version', $vendor_application_version)
    )
    return $installer_info
}

##########################################################################################
#
# Main Driver
#
##########################################################################################

if ($verbose_logging)
{
    run_log_print -log_message "Logging set to Debug." -log_level DEBUG 
}
run_log_print -log_message "Accepting MTD_Build_file=$mdt_build_tasklist" -log_level INFO

#We get content of the ./ts.xml (default parameter value). 
[xml]$mdt_ts = get-content $mdt_build_tasklist

#We get an array of all the steps which have a 'step' tag, and where the type is "BDD_InstallApplication".
$bdd_install_applications = $mdt_ts.GetElementsByTagName('step') | where-object { $_.type -eq "BDD_InstallApplication" }
run_log_print -log_message "Discovering_Artifacts_Required_Count=$( $bdd_install_applications.count )" -log_level INFO

#We loop through every element we extracted (which followed the above criteria), in the $valid_artifact_install_applications array. 
foreach ($installer in $bdd_install_applications)
{
    run_log_print -log_message "Discovering $( $installer.name )" -log_level INFO
    try
    {
        #We call the 'validate_installer_pattern' function to see if the $installer.name is actually to one of our standards.
        $artifact_info = validate_installer_pattern -installer_name $installer.name
        run_log_print -log_message "Artfact Match: Vendor=$( $artifact_info.vendor_name) Application=$( $artifact_info.vendor_application ) Version=$( $artifact_info.vendor_application_version )" -log_level DEBUG
    }
    catch
    {
        run_log_print -log_message "$_.Exception" -log_level WARN 
        continue
    }
    run_log_print -log_message "Checking Local_Destination=$local_destination target_directoy_name=$( $installer.name )" -log_level DEBUG
    #We call our 'check_artifact_already_present' to see if it is already in our cache. If it is, we do not need to increase web domain traffic with the retrieval from NEXUS.
    $artifact_present = check_artifact_already_present $local_destination $( $installer.name )
    if (-Not($artifact_present))
    {
        #If the artifact is not in our cache, we retrieve it.
        run_log_print -log_message "Retrieving_Artifact=$( $installer.name )" -log_level INFO
        retrieval_artifacts_from_artifact_store -artifact_info $artifact_info -local_destination $local_destination -target_directoy_name $installer.name
    }
    else
    {
        run_log_print -log_message "$( $installer.name ) already present, skipping." -log_level INFO
    }
}

##############################################################
#######
run_log_print -log_message "Script Completed" -log_level INFO 
if ($verbose_logging)
{
    write-output "######## Runtime Alerts ##########" 
    foreach ($key in $runtime_alerts.keys)
    {
        Write-Output "$key  $computer_name  $application_user  $( $runtime_alerts[$key][0] )  $( $runtime_alerts[$key][1] )"
    }
}
