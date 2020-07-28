# Variables 
$ClientName = "@companyname@"
$DuoAccountIntKey = "@accountintkey@"
$DuoAccountSecKey = "@accountseckey@"

# Should be something like "api-xxxxxxxx.duosecurity.com"
$APIHost = "@apihost@"

$NewUser = @{
    Username = "@username@"
    CellPhone = "@cellphone@"
    Email = "@email@"
    FirstName = "@firstname@"
    LastName = "@lastname@"
}
 

# Functions
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

function CheckIfUserExists {
    $Method = "GET"
    $script:DuoMethodPath = "/admin/v1/users"
      
    $APIParams = @{account_id = "$CompanyAccountId"
                   username = $NewUser.Username 
    }
     
    CreateRequest
     
    $Response = Invoke-RestMethod -Method $Method -Headers $DUOWebRequestParams.Headers -Uri $DUOWebRequestParams.URI `
                                  -Body $APIParams -ContentType $DUOWebRequestParams.ContentType
    $script:ActiveUsers = $Response.response | Where-Object status -like 'active' | Select-Object username
    $script:Users = $Response.response | Select-Object username
}

function CreateUser { 
    # If user doesn't exist, create user
    $Method = "POST"
    $script:DuoMethodPath = "/admin/v1/users"
    
    $APIParams = @{account_id = "$CompanyAccountId"
                username = $NewUser.Username
                firstname = $NewUser.FirstName
                lastname = $NewUser.LastName
                realname = $NewUser.FirstName + " " + $NewUser.LastName
                email = $NewUser.Email
                status = "active"
    }
    
    CreateRequest

    $script:Response = Invoke-RestMethod -Method $Method -Headers $DUOWebRequestParams.Headers -Uri $DUOWebRequestParams.URI `
                                         -Body $APIParams -ContentType $DUOWebRequestParams.ContentType

    $script:UserId = $Response.response.user_id
}

function EnableUser {
       $Method = "POST"
       $script:DuoMethodPath = "/admin/v1/users/$UserId"
       
       $APIParams = @{account_id = "$CompanyAccountId"
                   username = $NewUser.Username
                   firstname = $NewUser.FirstName
                   lastname = $NewUser.LastName
                   realname = $NewUser.FirstName + " " + $NewUser.LastName
                   email = $NewUser.Email
                   status = "active"
       }
       
       CreateRequest
   
       $script:Response = Invoke-RestMethod -Method $Method -Headers $DUOWebRequestParams.Headers -Uri $DUOWebRequestParams.URI `
                                            -Body $APIParams -ContentType $DUOWebRequestParams.ContentType
}

function CreatePhone {
    $Method = "POST"
    $script:DuoMethodPath = "/admin/v1/phones"

    $APIParams = @{
        account_id = "$CompanyAccountId"
        number = $NewUser.CellPhone
        name = "Cell phone"
        type = "mobile"
    }

    CreateRequest

    $script:Response = Invoke-RestMethod -Method $Method -Headers $DUOWebRequestParams.Headers -Uri $DUOWebRequestParams.URI `
                                         -Body $APIParams -ContentType $DUOWebRequestParams.ContentType
    
    $script:PhoneId = $Response.response.phone_id
}

function AssociatePhoneWithUser {
    $Method = "POST"
    $script:DuoMethodPath = "/admin/v1/users/$UserId/phones"

    $APIParams = @{
        account_id = "$CompanyAccountId"
        phone_id = $PhoneId
    }

    CreateRequest

    $script:Response = Invoke-RestMethod -Method $Method -Headers $DUOWebRequestParams.Headers -Uri $DUOWebRequestParams.URI `
                                         -Body $APIParams -ContentType $DUOWebRequestParams.ContentType
}


# Code Logic
GetCompanyAccountInfo

CheckIfUserExists

if ($null -ne $ActiveUsers) {
    Write-Output "This user already exists."
    exit
} elseif ($null -ne $Users) {
    Write-Output "Users exists but was not enabled. Enabling user. If user is in the trash, it will need to be manually restored."
    EnableUser
} else {
    Write-Output "Creating user."
    CreateUser
}

try {
    CreatePhone
} catch {
    Write-Output "Phone creation failed. It may already exist."
}

if (($null -ne $UserId) -and ($null -ne $PhoneId)) {
    AssociatePhoneWithUser
}