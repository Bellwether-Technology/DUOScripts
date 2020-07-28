# Variables 
$ClientName = "@companyname@"
$DuoAccountIntKey = "@accountintkey@"
$DuoAccountSecKey = "@accountseckey@"

# Should be something like "api-xxxxxxxx.duosecurity.com"
$APIHost = "@apihost@"

function CreateRequest {
    $BadOffset = Get-Date -Format "zzzz"
    $GoodOffset = $BadOffset -Replace ":",""
    [string]$date = Get-Date -Format "ddd, dd MMM yyyy HH:mm:ss $GoodOffset"

    # Stringified Params/URI Safe chars
    $StringAPIParams = ($APIParams.Keys | Sort-Object | ForEach-Object {
        $_ + "=" + [uri]::EscapeDataString($APIParams.$_)
    }) -join "&"

    $DuoParams = (@(
        $date.Trim(),
        $Method.ToUpper().Trim(),
        $APIHost.ToLower().Trim(),
        $DuoMethodPath.Trim(),
        $StringAPIParams.trim()
    ).trim() -join "`n").ToCharArray().ToByte([System.IFormatProvider]$UTF8)

    # Hash out some secrets 
    $HMACSHA1 = [System.Security.Cryptography.HMACSHA1]::new($DuoAccountSecKey.ToCharArray().ToByte([System.IFormatProvider]$UTF8))
    $hmacsha1.ComputeHash($DuoParams) | Out-Null
    $ASCII = [System.BitConverter]::ToString($hmacsha1.Hash).Replace("-", "").ToLower()
    
    # Create the new header and combing it with our Integration Key to use it as Authentication
    $AuthHeader = $DuoAccountIntKey + ":" + $ASCII
    [byte[]]$ASCIBytes = [System.Text.Encoding]::ASCII.GetBytes($AuthHeader)

    # Create our Parameters for the webrequest - Easy @Splatting!
    $script:DUOWebRequestParams = @{
        URI         = ('https://{0}{1}' -f $APIHost, $DuoMethodPath)
        Headers     = @{
            "X-Duo-Date"    = $Date
            "Authorization" = ('Basic: {0}' -f [System.Convert]::ToBase64String($ASCIBytes))
        }
        Body        = $APIParams
        Method      = $Method
        ContentType = 'application/x-www-form-urlencoded'
    }
}

function GetCompanyAccountInfo {
    $Method = "POST"
    $script:DuoMethodPath = "/accounts/v1/account/list"
    
    # Example of APIParams would be @{username='JoeTheUser'}
    $APIParams = ""

    CreateRequest

    $Response = Invoke-RestMethod -Method $Method -Headers $DUOWebRequestParams.Headers -Uri $DUOWebRequestParams.URI `
                                  -Body $APIParams -ContentType  $DUOWebRequestParams.ContentType
    $Companies = $Response.response
    $CompanyId = $Companies | Where-Object name -like "$ClientName" | Select-Object account_id
    $script:CompanyAccountId = $CompanyId.account_id
}

function GetUserCount {
 
$Method = "GET"
$script:DuoMethodPath = "/admin/v1/users"
 

$APIParams = @{account_id = "$CompanyAccountId"
    limit = 300
}
 
CreateRequest
 
$Response = Invoke-RestMethod -Method $Method -Headers $DUOWebRequestParams.Headers -Uri $DUOWebRequestParams.URI -Body $APIParams -ContentType $DUOWebRequestParams.ContentType
$script:Usernames = $Response.response | Where-Object status -like 'active' | Select-Object realname
}


# Code Logic
GetUserCount

Write-Output $Usernames.Count


# Notes:
# This will only pull the first 300 users. For our purposes, this was preferable to using the 
# /admin/v1/info/summary endpoint, because we specifically wanted to find the number of enabled
# users and we don't have any tenants with more than 300 users.
# If there are more than 300 users, we would need to add a function to deal with the pagination.
# As mentioned before, /admin/v1/info/summary could also be used, but the count includes disabled
# users and even users who are currently in the trash.