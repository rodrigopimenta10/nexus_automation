<#
.SYNOPSIS
    You can feed this script a task sequece ts.xml (in this case it's the Serenity TS) and it parses all the software 
    components the task sequence uses. Then the script pulls down from NEXUS the software components which
    are required by the task sequence, if it is not already in the cache, to the cached location.
    Finally, the script unpacks the software component to the 'Applications' folder of the deployment share if that
    switch is turned on.

.DESCRIPTION
    Example: Local testing:
        cd C:\Users\zk787uq\Desktop\testing
        ./component retrieval.psl -mdt build_tasklist "./ts.xml" -local destinatio n "C:\Users\zk787uq\Desktop\testing\Applications" -cache Folder "VendorDeliveryCache" - verbose_logging

    Consideration:
        This script will be run on build server 123 (specifically on the D:\ drive 1 through a Jenkins job.
        
        cd E:\testing_1
        ./component retrieval.psl-mdt build tasklist "./ts.xml" -local destinatio n "E:\Windows_10testing\Applications" -cache Folder "VendorDeliveryCacheTesting" -verbo se_logging

    Jenkins:
        cd ATMCICD-206
        ./component_retrieval.psl-mdt_build_tasklist "./ts.xml" -local destinatio n "E:\Windows_10testing\Applications" -cache Folder "VendorDeliveryCacheTesting" -unpac kToDeploymentShare -verbose_logging
        
    We take four optional parameters.

.PARAMETER $mdt_build_tasklist
    The path to the XML file to parse and extract all the software component elements information inside.

.PARAMETER $local destination

.PARAMETER $cache Folder
    The name of the folder you would like to create in the current drive (the drive th is script is run on) to be your
    cache folder.

.PARAMETER $verbose_logging
#>
param (
    [Parameter (Mandatory = $false)][string] $mdt_build_tasklist = "ts, xml",
    [Parameter (Mandatory = $false)][string] $local_destination = "C:\Users\zk787uq\Desk top\testingTwo \Applications",
    [Parameter (Mandatory = $false)][string] $cacheFolder = "VendorDeliveryCache", 
    [Parameter (Mandatory = $false)][switch] $verbose_logging
    )

$Logfile = "C:\Users\rodri\Documents\BA\testingTwo"
