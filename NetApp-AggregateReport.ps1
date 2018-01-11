#Script Help
#----------

<#
	.SYNOPSIS
    
		NetApp-AggregateReport.ps1 will send an email to a specified address with a list of detected aggregates on
		any CDOT cluster.  This script als attaches a csv file of the data and saves the file to the script directory.

		Version History:

			[x] Version 1.0 (Release) - 01/09/18

		Requirements:
            
            This script was built and tested on the following versions of:

			NetApp DataONTAP Powershell Module v4.0.0 and v4.1
            Powershell v4.0 and v5.1
            Clustered DataONTAP 9.1
            

    .DESCRIPTION
 
        NetApp-AggregateReport.ps1 will send an email to a specified address with a list of detected aggregates on
		any CDOT cluster.  This report will also save and send an attached csv file.

	.PARAMETER  Clusters
 
		One or more NetApp Data ONTAP cmode clusters specified by IP or hostname.
 
	.PARAMETER  Username
 
		Local admin username for the specified cluster(s).

	.PARAMETER  Password
 
		Password for specified username.

	.PARAMETER SendMail
 
		Send e-mail option ($true/$false). The default value is "$false".

	.PARAMETER SMTPServer
 
		Mail server address.

	.PARAMETER SMTPPort
 
		Mail server port. The default value is "25".

	.PARAMETER MailTo
 
		A single mail recipient or an array of mail recipients. Use comma to separate recipients.

	.PARAMETER MailFrom
 
		Mail sender address.

	.PARAMETER MailFromPassword
 
		Mail sender password for SMTP authentication.

	.PARAMETER SMTPServerTLSorSSL
 
		SMTP TLS/SSL option ($true/$false). The default value is "$false".
		 
	.EXAMPLE

		Report clusters cluster1 and cluster2 for aggregate capacity, and email report.

		.\NetApp-AggregateReport.ps1 -Cluster controller1,controller2 -Username <user> -Password <"pass"> -SMTPServer <server> -MailFrom <Email From> -MailTo <Email To>
 
	.INPUTS
 
		None
 
	.OUTPUTS
 
		None
 
	.NOTES
 
		Author: James Castro
		Email: james.castro@netapp.com
		Date created: 01/09/18
		Last modified: 01/09/18
		Version: 1.0
		Thanks to https://nmanzi.com and a few others for the inspiration in which this report is based on.  I've combined several solutions and added some of my own tricks
        to build this report.

	.LINK    
        https://storagedevops.blogspot.com/

#>

#end Script Help

#Script Parameters
# -----------------------

[CmdletBinding(SupportsShouldProcess=$True)]
Param (
    
    [parameter(
                Mandatory=$true,
                HelpMessage='NetApp Cluster name/IPs separated by commas (like netapp01,netapp02 or 192.168.1.1,192.168.1.2)')]
               
                [string[]]$Clusters,

    [parameter(
                Mandatory=$true,
                HelpMessage='Username for NetApp Clusters')]
               
                [string]$Username,

    [parameter(
                Mandatory=$true,
                HelpMessage='Password to suit username provided')]
               
                [string]$Password,

    [parameter(
                Mandatory=$false,
                HelpMessage='Enable Send Mail (This is just a switch, value can not be assigned)')]
               
                [bool]$SendMail = $false,

    [parameter(
                Mandatory=$false,
                HelpMessage='SMTP Server Address (Like IP address, hostname or FQDN)')]
            
                [string]$SMTPServer,

    [parameter(
                Mandatory=$false,
                HelpMessage='SMTP Server port number (Default 25)')]
            
                [int]$SMTPPort = "25",

    [parameter(
                Mandatory=$false,
                HelpMessage='Mail To (Recipient e-mail address)')]
               
                [array]$MailTo,

    [parameter(
                Mandatory=$false,
                HelpMessage='Mail From (Sender e-mail address)')]
               
                [string]$MailFrom,

    [parameter(
                Mandatory=$false,
                HelpMessage='For SMTP Authentication (Sender e-mail address password)')]
               
                [string]$MailFromPassword,

    [parameter(
                Mandatory=$false,
                HelpMessage='SMTP TLS/SSL option ($true/$false). The default is "$fale".')]
            
                [bool]$SMTPServerTLSorSSL = $false
)

#end Script Parameters

Import-Module DataONTAP


#Functions
#---------

Function getCredObject {

    $strPass = ConvertTo-SecureString -String $Password -AsPlainText -Force
    $objCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($Username, $strPass)
    
    return $objCred
}

#Variables
#---------

$CurrentDate = Get-Date -Format F
$CurrentDate1= Get-Date -Format MMddyyyy
$exedir = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$outfile = ($exedir + "\" + "Aggregate_Monthly_" + $CurrentDate1 + ".csv")

#HTML Build for email
#--------------------

$htmlEmailHead = "
<head>
<style>
body{
    width:100%;
    min-width:1024px;
    font-family: Verdana, sans-serif;
    font-size:14px;
    /*font-weight:300;*/
    line-height:1.5;
    color:#222222;
    background-color:#fcfcfc;
}

p{
    color:#000000;
}

strong{
    font-weight:600;
}

h1{
    font-size:30px;
    font-weight:300;
}

h2{
    font-size:20px;
    font-weight:300;
}

#ReportBody{
    width:95%;
    height:500;
    /*border: 1px solid;*/
    margin: 0 auto;
}

table{
    width:100%;
    min-width:1010px;
    /*table-layout: fixed;*/
    border-collapse: collapse;
    border: 1px solid #ccc;
    /*margin-bottom:15px;*/
}

/*Row*/
tr{
    font-size: 12px;
}

tr:nth-child(odd){
    background:#F9F9F9;
}

/*Column*/
td {
    padding:10px 8px 10px 8px;
    font-size: 12px;
    border: 1px solid #ccc;
    text-align:center;
    vertical-align:middle;
}

/*Table Heading*/
th {
    background: #0066ff;
    border: 1px solid #ccc;
    font-size: 14px;
    font-weight:bold;
    padding:12px;
    text-align:center;
    vertical-align:middle;
}
</style></head>
<h1>NetApp Aggregate Report</h1>
<hr/>
<p>Aggregate capacities in GB as of <b>$CurrentDate</b></p><hr/>"

$htmlEmailTableHead = "
<table>
<tbody>
<tr>
<th><p>Cluster</p></th>
<th><p>Aggregate</p></th>
<th><p>Node</p></th>
<th><p>SizeTotal</p></th>
<th><p>LogicalSpaceUsed</p></th>
<th><p>PhysicalSpaceUsed</p></th>
<th><p>VolCount</p></th>
</tr>"

$htmlEmailTableFooter = "</tbody></table>"

$htmlEmailContent = $null

$htmlEmail = $null

$sendEmail = $false


#Program
#-------

#declare object array so that we can place in a csv file to email

$emailOBJ = @()


foreach ($Cluster in $Clusters) {
    
    $CurrentCluster = Connect-NcController -Name $Cluster -Credential (getCredObject)

#build aggregate query template so we can include several attributes that house details such as "PhysicalSpaceUsed"

    $aggrQuery = Get-NcAggr -Template
        Initialize-NcObjectProperty -Object $aggrQuery -Name Name,Nodes,AggrSpaceAttributes,AggrVolumeCountAttributes

#gather info on the cluster so that we can use the clean version of the cluster name (not the FQDN).

    $ClusterName = Get-NcCluster

#command to gather the aggregate info we need using the aggregate query
    $AggList = Get-NcAggr  -Query $aggrQuery -Controller $CurrentCluster

    if ($AggList) {

            $sendEmail = $true
            $htmlEmailContent += "<h3>$($ClusterName.ClusterName) ($($AggList.Count) aggregates)</h3>" + $htmlEmailTableHead

        foreach ($Agg in $AggList) {           
                    #pulling out desired data, convert raw numbers to GB
                    $NameCluster = $clustername.ClusterName  
                    $Aggregate = $Agg.Name
                    $Node = $Agg.AggrOwnershipAttributes.HomeName
                    $SizeTotal = [math]::Round($Agg.AggrSpaceAttributes.SizeTotal / 1GB,2)
                    $LogicalSpaceUsed = [math]::Round($Agg.AggrSpaceAttributes.SizeUsed / 1GB,2)
                    $PhysicalSpaceUsed = [math]::Round($Agg.AggrSpaceAttributes.PhysicalUsed / 1GB,2)                    
                    $VolCount = $Agg.AggrVolumeCountAttributes.FlexvolCount

                    #add results to email table
                    $htmlEmailContent += "<tr><td><p>$NameCluster</p></td><td><p>$Aggregate</p></td><td><p>$Node</p></td><td><p>$SizeTotal</p></td><td><p>$LogicalSpaceUsed</p></td><td><p>$PhysicalspaceUsed</p></td><td><p>$VolCount</p></td></tr>"

                    #build array and place the content into the emailOBJ
                    $aggdetail = @{'Cluster'=$NameCluster;
                                   'Aggregate'=$Aggregate;
                                   'Node'=$Node;
                                   'SizeTotal'=$SizeTotal;
                                   'LogicalSpaceUsed'=$LogicalSpaceUsed;
                                   'PhysicalSpaceUsed'=$PhysicalSpaceUsed;
                                   'VolCount'=$VolCount}
                    $objectA = New-Object -TypeName PSObject -Property $aggdetail
                    $emailOBJ += $objectA

            }
#place object array into a csv file and save to path
$emailOBJ | Select Cluster,Aggregate,Node,SizeTotal,LogicalSpaceUsed,PhysicalSpaceUsed,VolCount | Export-Csv -Path $outfile -NoTypeInformation

                $htmlEmailContent += $htmlEmailTableFooter 

                $htmlEmailContent += "<hr/>"

        }

}

if ($sendEmail -and $htmlEmailContent) {

    $htmlEmail = $htmlEmailHead + $htmlEmailContent
    Write-Host "Report built, sending..."

} else {

    Write-Host "Nothing to report on, so I'm exiting"
    Break

}

#Send Mail with attached file
#----------------------------

if ($SendMail -or $SMTPServer)
{
    if ($SMTPServer -and $MailFrom -and $MailTo -and $htmlEmail)
    {

        $subject = "NetApp Aggregate Report"
        $MailTo = ($MailTo -join ',').ToString()
        $mailMessage = New-Object System.Net.Mail.MailMessage
        $mailMessage.subject = $subject
        $mailMessage.to.add($MailTo)
        $mailMessage.from = $MailFrom
        $mailMessage.body = $htmlEmail
        $mailMessage.IsBodyHtml = $true
        $mailMessage.Attachments.Add($outfile)
        $smtp = New-Object System.Net.Mail.SmtpClient($SMTPServer, $SMTPPort);

        if ($MailFromPassword)
        {
            $smtp.UseDefaultCredentials = $false
            $smtp.Credentials = New-Object System.Net.NetworkCredential($MailFrom, $MailFromPassword);
        }
        
        if ($SMTPServerTLSorSSL)
        {
            $smtp.EnableSSL = $true
        }
        
        $smtpSendResult = 1
        Try
        {
            $smtp.send($mailMessage)
        }
        Catch
        {
            Write-Error -Message "E-Mail could not be sent"
            $smtpSendResult = 0
        }

        if ($smtpSendResult -eq 1)
        {
            Write-Debug -Message "E-mail has been sent to the address(es): $MailTo"
        }

        Remove-Variable -Name smtp
        Remove-Variable -Name MailFromPassword
    }
}

exit


