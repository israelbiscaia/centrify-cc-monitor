#INSTALL#
# "Set-ExecutionPolicy Unrestricted" Must be set using the following PowerShell Management Shells run as Administrator
# C:\Windows\SysWOW64\WindowsPowerShell\v1.0\powershell.exe
# C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe

param (
[string]$server = "pod1.centrify.com/", #Centrify pod URL
[string]$username = "admin@cenrifytenant.com", #Tenant reporting-capable username. This user must be a member of a role that is allowed password-only authentication.
[string]$password = "Centrify", #Tenant admin password
$eventId = "1010", #Event ID to be written to the Event Log in case the Centrify Cloud Connector service is down
$eventType = "Warning", #Event type to be written to the Event Log in case the Centrify Cloud Connector service is down
$eventMessageCCOffline = "Centrify Connector is Inactive", #Event type to be written to the Event Log in case the Centrify Cloud Connector service is inactive
$eventMessageServiceStopped = "Centrify Connector is being stopped", #Event type to be written to the Event Log in case the Centrify Cloud Connector service is down
$eventMessageServiceStarted = "Centrify Connector is being started", #Event type to be written to the Event Log in case the Centrify Cloud Connector service is inactive
$SleepSeconds = "30", #Number of seconds to sleep between stop and restart service
$ServiceArray = "adproxy", #Name of service(s) to stop and restart
[string]$ContentType = "application/json",

$ReportQuery = "select machinename from proxy where machinename like '" + $env:computername + "' and proxy.Online = 0"

)

#Login is required for all other rest calls to get auth token
Function Login()
{ 
    $LoginJson = "{user:'$username', password:'$password'}"
    $LoginHeader = @{"X-CENTRIFY-NATIVE-CLIENT"="1"}
    $Login = invoke-WebRequest -Uri "https://$server/security/login" -ContentType $ContentType -Method Post -Body $LoginJson -SessionVariable websession -UseBasicParsing

    $cookies = $websession.Cookies.GetCookies("https://$server/security/login") 

    $ASPXAuth = $cookies[".ASPXAUTH"].value
    return $ASPXAuth    
}

#RunQuery function
Function RunQuery($Auth, $Query)
{
    $QueryHeaders = @{"X-CENTRIFY-NATIVE-CLIENT"="1";"Authorization" = "Bearer " + $Auth}
    $QueryJson = $Query

    $ExecuteQuery = Invoke-RestMethod -Method Post -Uri "https://$server/RedRock/query" -Body $QueryJson -ContentType $ContentType -Headers $QueryHeaders 

    Write-Host "Query Success = $ExecuteQuery.success"
    Write-Host $ExecuteQuery.MessageID

    return $ExecuteQuery.result
}

#Query Cloud Connectors table in the cloud and restart CC service if CC is Inactive
Function CheckProxy()
{
    $AuthToken = Login
    $QueryResult = RunQuery $AuthToken "{""Script"":""$ReportQuery""}"
    $ReportBody = ""

    foreach ($result in $QueryResult)
    {
        foreach ($row in $result.Results)
        {
            #extract machine name from query result (trim 14 characters at the beginning (@{machinename=) and the trailing }
            [string]$rowValue = $row.Row
            $rowValue = $rowValue.Substring(14);
            $rowValue = $rowValue.TrimEnd("}");
            
            if($rowValue -eq $env:computername)
            {
                Restart_Service($env:computername)
            }
        }
    }
}

#Stop and restart CC service
Function Restart_Service($Computer)
{

    #Stop Service
    Write-EventLog -LogName "Application" -Source "adproxy" -EventId $eventId -EntryType $eventType -Message $eventMessageServiceStopped
    Stop-Service -displayname "Centrify Connector"
    
    #Sleep for 30 seconds
    Start-Sleep -Seconds $SleepSeconds

    #Start Service
    Write-EventLog -LogName "Application" -Source "adproxy" -EventId $eventId -EntryType $eventType -Message $eventMessageServiceStarted
    Start-Service -displayname "Centrify Connector"
}

CheckProxy
