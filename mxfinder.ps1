# this script written by zwerd.
# אhis פowerדhell script retrieves the MX (Mail Exchange) records of a specified primary domain and checks whether other domains (provided in a text file) use any of the same mail servers.

param (
    [Parameter(Mandatory = $true)]
    [string]$d,  # Primary domain to extract MX records from

    [Parameter(Mandatory = $true)]
    [string]$l   # Path to file with list of domains to check
)

Write-Host "`n--- Step 1: Extracting MX records for domain $d ---" -ForegroundColor Yellow
try {
    $primaryMXResults = nslookup -type=mx $d 2>&1

    $primaryMXRecords = $primaryMXResults | Where-Object { $_ -match "mail exchanger = " } | ForEach-Object {
        ($_ -split "mail exchanger = ")[1].Trim().ToLower()
    }

    if ($primaryMXRecords.Count -eq 0) {
        Write-Host "No MX records found for $d" -ForegroundColor Red
        exit
    }

    Write-Host "Found mail servers:" -ForegroundColor Cyan
    $primaryMXRecords | ForEach-Object { Write-Host " - $_" }

} catch {
    Write-Host "Error retrieving MX records for domain $d" -ForegroundColor Red
    exit
}

Write-Host "`n--- Step 2: Checking domains from list $l ---" -ForegroundColor Yellow

if (!(Test-Path $l)) {
    Write-Host "File $l not found." -ForegroundColor Red
    exit
}

$domainsToCheck = Get-Content -Path $l

foreach ($domain in $domainsToCheck) {
    $domain = $domain.Trim()
    if ($domain -eq "") { continue }

    try {
        $nslookupResult = nslookup -type=mx $domain 2>&1
        $mxRecords = $nslookupResult | Where-Object { $_ -match "mail exchanger = " } | ForEach-Object {
            ($_ -split "mail exchanger = ")[1].Trim().ToLower()
        }

        $matchingMX = $mxRecords | Where-Object { $primaryMXRecords -contains $_ }

        if ($matchingMX.Count -gt 0) {
            Write-Host "`n[$domain] uses one or more matching mail servers:" -ForegroundColor Green
            $matchingMX | ForEach-Object { Write-Host " -> $_" -ForegroundColor Cyan }
        } else {
            Write-Host "[$domain] does not use any of the specified mail servers." -ForegroundColor Gray
        }

    } catch {
        Write-Host "Error checking domain $domain" -ForegroundColor Red
    }
}
