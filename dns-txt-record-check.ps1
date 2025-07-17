param(
    [switch]$spf,
    [switch]$dkim,
    [switch]$dmarc,
    [switch]$flag,
    [switch]$help,
    [string]$selector = "default",
    [string]$domain,
    [string]$file,
    [string]$dns
)

function Show-Help {
    Write-Host ""
    Write-Host "Usage examples:" -ForegroundColor Cyan
    Write-Host "  .\dns-txt-record-check.ps1 -spf -domain example.com"
    Write-Host "  .\dns-txt-record-check.ps1 -dkim -selector default -domain example.com"
    Write-Host "  .\dns-txt-record-check.ps1 -dmarc -file domains.txt"
    Write-Host "  .\dns-txt-record-check.ps1 -spf -domain example.com -flag"
    Write-Host "  .\dns-txt-record-check.ps1 -spf -domain example.com -dns 1.1.1.1"
    Write-Host ""
    Write-Host "Flags:"
    Write-Host "  -spf             Check SPF record"
    Write-Host "  -dkim            Check DKIM record"
    Write-Host "  -dmarc           Check DMARC record"
    Write-Host "  -selector <sel>  Specify DKIM selector (default: 'default')"
    Write-Host "  -domain <name>   Domain to check"
    Write-Host "  -file <path>     File with list of domains (one per line)"
    Write-Host "  -dns <ip>        DNS server to use"
    Write-Host "  -flag            Output only the record text"
    Write-Host "  -help            Show this help menu"
    Write-Host ""
    exit 0
}

if ($help) { Show-Help }

function Resolve-Record {
    param($Name, $Type)

    if ($dns) {
        try {
            return Resolve-DnsName -Name $Name -Type $Type -Server $dns -ErrorAction SilentlyContinue
        } catch {
            return $null
        }
    } else {
        try {
            return Resolve-DnsName -Name $Name -Type $Type -ErrorAction SilentlyContinue
        } catch {
            return $null
        }
    }
}

function Check-SPF {
    param (
        [string]$Domain,
        [string]$DnsServer = $dns
    )

    try {
        if ($DnsServer) {
            $records = Resolve-Record -Name $Domain -Type TXT -Server $DnsServer -ErrorAction Stop 
        }
        else {
            $records = Resolve-DnsName -Name $Domain -Type TXT -ErrorAction Stop 
        }
    }
    catch {
        Write-Host "[$Domain] Failed to retrieve SPF record" -ForegroundColor Red
        return
    }

    # Find all TXT records where any string (after trim) starts with v=spf1
    $spfRecords = @()
    foreach ($rec in $records) {
        foreach ($txt in $rec.Strings) {
            if ($txt.TrimStart() -like "v=spf1*") {
                # Combine all strings of this record to one SPF string with spaces between parts
                $spfRecords += ($rec.Strings -join " ")
                break
            }
        }
    }

    if (-not $spfRecords -or $spfRecords.Count -eq 0) {
        Write-Host "[$Domain] No SPF record found" -ForegroundColor Red
        return
    }

    if ($spfRecords.Count -gt 1) {
        Write-Host "[$Domain] Warning: Multiple SPF records found. Processing the first one." -ForegroundColor Yellow
    }

    $spfString = $spfRecords[0].Trim()

    # Check enforcement
    $hasStrictAll = $spfString -match "\-all"
    $hasSoftAll = $spfString -match "(~all|\+all|\?all)"

    if (-not $hasStrictAll) {
        Write-Host "[$Domain] SPF record found but missing strict '-all'" -ForegroundColor Red
        #Write-Host "`"$spfString`"" -ForegroundColor Red
        #return
    }

    if ($hasSoftAll) {
        Write-Host "[$Domain] SPF record found but has soft/neutral fail (~all, +all, ?all)" -ForegroundColor Red
        #Write-Host "`"$spfString`"" -ForegroundColor Red
        #return
    }

    # Split SPF string to parts
    $parts = $spfString -split "\s+"

    Write-Host "[$Domain] SPF record found and policy is strict" -ForegroundColor Green

    # Print each part with color separately
    foreach ($part in $parts) {
        if ($part -like "include:*" -or $part -like "exists:*" -or $part -like "redirect=" -or $part -like "exp=") {
            Write-Host "$part" -ForegroundColor Yellow -NoNewline
            Write-Host " " -NoNewline
        }
        elseif ($part -like "mx" -or $part -like "ptr" -or $part -like "-all" -or $part -like "v=spf1") {
            Write-Host "$part" -ForegroundColor Green -NoNewline
            Write-Host " " -NoNewline
        }
        elseif ($part -like "a" -or $part -like "ip4:*" -or $part -like "ip6:*" -or $part -like "~all") {
            Write-Host "$part" -ForegroundColor Red -NoNewline
            Write-Host " " -NoNewline
        }
        else {
            Write-Host "$part" -ForegroundColor Green -NoNewline
            Write-Host " " -NoNewline
        }
    }

    Write-Host ""  # New line at end
}

function Check-DKIM {
    param(
        [string]$Domain,
        [string]$Selector
    )

    $dkimName = "$Selector._domainkey.$Domain"

    try {
        $records = Resolve-Record -Name $dkimName -Type TXT -ErrorAction Stop | Where-Object {
            $_.Strings -match "^v=DKIM1"
        }
    }
    catch {
        Write-Host "[$Domain] Failed to retrieve DKIM record ($Selector)" -ForegroundColor Red
        return
    }

    if ($records -and $records.Count -gt 0) {
        # Combine all strings from the record into one string (sometimes TXT is split)
        $dkimString = ($records[0].Strings) -join ""

        # Extract key type if present
        if ($dkimString -match "k=([^;]+)") {
            $keyType = $matches[1]
        }
        else {
            $keyType = "rsa"  # default key type
        }

        # Check if key type is rsa (green), else warn (yellow)
        if ($keyType -ieq "rsa") {
            Write-Host "[$Domain] DKIM record ($Selector) found valid (key type: $keyType)" -ForegroundColor Green
        }
        else {
            Write-Host "[$Domain] DKIM record ($Selector) found with unusual key type: $keyType" -ForegroundColor Yellow
        }

        # Print the full DKIM record string in green
        Write-Host "`"$dkimString`"" -ForegroundColor Green
    }
    else {
        Write-Host "[$Domain] DKIM record ($Selector) not found or invalid" -ForegroundColor Red
    }
}

function Check-DMARC {
    param($Domain)
    $dmarcName = "_dmarc.$Domain"

    try {
        $records = Resolve-Record -Name $dmarcName -Type TXT -ErrorAction Stop | Where-Object { $_.Strings -match "^v=DMARC1" }
    }
    catch {
        Write-Host "[$Domain] Failed to retrieve DMARC record" -ForegroundColor Red
        return
    }

    if (-not $records) {
        Write-Host "[$Domain] DMARC record not found" -ForegroundColor Red
        return
    }

    $dmarcString = ($records[0].Strings -join " ").Trim()

    # Parse DMARC tags into a hashtable
    $tags = @{}
    foreach ($tag in $dmarcString -split ";") {
        $tag = $tag.Trim()
        if ($tag -match "^([^=]+)=(.+)$") {
            $tags[$matches[1].ToLower()] = $matches[2]
        }
    }

    Write-Host "[$Domain] DMARC record found:" -ForegroundColor Green
    Write-Host "`"$dmarcString`""

    # Define explanations for each tag
    $explanations = @{
        v     = "Version of DMARC protocol (must be DMARC1)"
        p     = "Policy for domain (none, quarantine, reject)"
        sp    = "Subdomain policy (overrides p for subdomains)"
        rua   = "Aggregate report URIs (where to send reports)"
        ruf   = "Forensic report URIs (optional detailed reports)"
        pct   = "Percentage of messages subjected to policy"
        aspf  = "SPF alignment mode (r=relaxed, s=strict)"
        adkim = "DKIM alignment mode (r=relaxed, s=strict)"
        fo    = "Failure reporting options (0,1,d,s or combinations)"
        rf    = "Report format (afrf or iodef)"
        ri    = "Report interval in seconds"
    }

    # Validate and color output function with explanation
    function Write-DmarcTag {
        param($key, $value, $status)

        switch ($status) {
            'valid'   { $color = "Green" }
            'warn'    { $color = "Yellow" }
            'error'   { $color = "Red" }
            default   { $color = "White" }
        }

        $explanation = if ($explanations.ContainsKey($key)) { $explanations[$key] } else { "No explanation available" }
        Write-Host ("{0,-6} = {1,-30} [{2}]" -f $key, $value, $explanation) -ForegroundColor $color
    }

    # Validate version (v)
    if ($tags.ContainsKey('v') -and $tags['v'] -eq 'DMARC1') {
        Write-DmarcTag "v" $tags['v'] "valid"
    }
    else {
        Write-DmarcTag "v" ($tags['v'] -or 'Missing or invalid') "error"
    }

    # Validate policy (p)
    $validPolicies = @('none', 'quarantine', 'reject')
    if ($tags.ContainsKey('p')) {
        if ($validPolicies -contains $tags['p'].ToLower()) {
            Write-DmarcTag "p" $tags['p'] "valid"
        }
        else {
            Write-DmarcTag "p" $tags['p'] "error"
        }
    }
    else {
        Write-DmarcTag "p" "Missing" "error"
    }

    # Validate subdomain policy (sp) – optional
    if ($tags.ContainsKey('sp')) {
        if ($validPolicies -contains $tags['sp'].ToLower()) {
            Write-DmarcTag "sp" $tags['sp'] "valid"
        }
        else {
            Write-DmarcTag "sp" $tags['sp'] "error"
        }
    }
    else {
        Write-DmarcTag "sp" "Not set (default applies)" "warn"
    }

    # Validate rua (aggregate reports) – optional but recommended
    if ($tags.ContainsKey('rua')) {
        Write-DmarcTag "rua" $tags['rua'] "valid"
    }
    else {
        Write-DmarcTag "rua" "Missing (recommended to set)" "warn"
    }

    # Validate ruf (forensic reports) – optional
    if ($tags.ContainsKey('ruf')) {
        Write-DmarcTag "ruf" $tags['ruf'] "valid"
    }
    else {
        Write-DmarcTag "ruf" "Missing (optional)" "warn"
    }

    # Validate pct (percentage) – optional, default 100
    if ($tags.ContainsKey('pct')) {
        if ([int]::TryParse($tags['pct'], [ref]$null) -and ($tags['pct'] -ge 0) -and ($tags['pct'] -le 100)) {
            Write-DmarcTag "pct" $tags['pct'] "valid"
        }
        else {
            Write-DmarcTag "pct" $tags['pct'] "error"
        }
    }
    else {
        Write-DmarcTag "pct" "100 (default)" "warn"
    }

    # Validate aspf (SPF alignment) – optional
    if ($tags.ContainsKey('aspf')) {
        if ($tags['aspf'] -in @('r', 's')) {
            Write-DmarcTag "aspf" $tags['aspf'] "valid"
        }
        else {
            Write-DmarcTag "aspf" $tags['aspf'] "error"
        }
    }
    else {
        Write-DmarcTag "aspf" "Not set (default r)" "warn"
    }

    # Validate adkim (DKIM alignment) – optional
    if ($tags.ContainsKey('adkim')) {
        if ($tags['adkim'] -in @('r', 's')) {
            Write-DmarcTag "adkim" $tags['adkim'] "valid"
        }
        else {
            Write-DmarcTag "adkim" $tags['adkim'] "error"
        }
    }
    else {
        Write-DmarcTag "adkim" "Not set (default r)" "warn"
    }

    # Validate fo (failure reporting options) – optional
    if ($tags.ContainsKey('fo')) {
        # Allowed values: 0, 1, d, s or combinations separated by :
        if ($tags['fo'] -match '^(0|1|d|s)(:(0|1|d|s))*$') {
            Write-DmarcTag "fo" $tags['fo'] "valid"
        }
        else {
            Write-DmarcTag "fo" $tags['fo'] "error"
        }
    }
    else {
        Write-DmarcTag "fo" "Not set (default 0)" "warn"
    }

    # Validate rf (report format) – optional
    if ($tags.ContainsKey('rf')) {
        # Commonly afrf or iodef
        if ($tags['rf'].ToLower() -in @('afrf', 'iodef')) {
            Write-DmarcTag "rf" $tags['rf'] "valid"
        }
        else {
            Write-DmarcTag "rf" $tags['rf'] "error"
        }
    }
    else {
        Write-DmarcTag "rf" "Not set (default afrf)" "warn"
    }

    # Validate ri (report interval) – optional
    if ($tags.ContainsKey('ri')) {
        if ([int]::TryParse($tags['ri'], [ref]$null) -and $tags['ri'] -ge 0) {
            Write-DmarcTag "ri" $tags['ri'] "valid"
        }
        else {
            Write-DmarcTag "ri" $tags['ri'] "error"
        }
    }
    else {
        Write-DmarcTag "ri" "Not set (default 86400)" "warn"
    }
}


# Input validation
if ($domain -and $file) {
    Write-Error "Cannot use both -domain and -file."
    exit 1
}

$domains = @()

if ($domain) {
    $domains = @($domain)
} elseif ($file) {
    if (-not (Test-Path $file)) {
        Write-Error "File '$file' not found."
        exit 1
    }
    $domains = Get-Content $file | Where-Object { $_ -and ($_ -notmatch "^\s*#") }
} else {
    Write-Error "You must specify either -domain or -file."
    exit 1
}

# Run checks
foreach ($d in $domains) {
    if ($spf) { Check-SPF -Domain $d }
    if ($dkim) { Check-DKIM -Domain $d -Selector $selector }
    if ($dmarc) { Check-DMARC -Domain $d }
}
