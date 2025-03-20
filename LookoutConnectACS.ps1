# Filename: 20241228.ps1, LookoutConnectACS
# First created: 20241228
# Last update: 20250103
# Author: @jiansuo
# To get image from camera periodically, upload it to LookOut Wildfire Detection SaaS and measure processing time.
# To output upload results to a file.
# To trigger ACS (AXIS Camera Station) to pop-up message(s) if there is bounding box(es) in LookOut reply. 
# This PowerShell script is intended to run for 24-hour or less every day by Windows Task Scheduler.
# LookOut Wildfire Detection SaaS website, https://lookout.roboticscats.com

# Define script parameters
param (
    # Default value for interation is 3, min is 1 and max is 1440 (24 hr x 60 min / hr)
    [ValidateRange(1,1440)][int]$Iteration = 3, 
    # Default value for wait time is 30-second, min is 15 and max is 300 (5 minutes)
    [ValidateRange(15,300)][int]$WaitTime = 30,
     # the switch parameter to list each iteration result
    [switch]$ListResults
)

# Define variables
# $cameraUrl is the image source. REPLACE with your camera URL 
$cameraUrl = "http://192.168.100.7/axis-cgi/jpg/image.cgi?resolution=1920X1080"

$username = "userA" # REPLACE with your camera username
$password = "passwordA" # REPLACE with your camera password
# $outputFile = "/Users/userA/Documents/powershell/LookoutConnectACS/1.jpg" # macOS path
$outputFile = "C:\Users\userA\Documents\PowerShell\LookoutConnectACS\1.jpg" # Windows 11 path
# $outputFile = "C:\Users\userA\Documents\PowerShell\testImage.jpg" # Windows 11 path
# $apiURL is the LookOut Camera Endpoint
# LookOut Camera Endpoint. REPLACE with your LookOut Camera Endpoint
$apiUrl = "https://lax.pop.roboticscats.com/api/detects?apiKey=..."
# $resultsFile = "/Users/userA/Documents/powershell/LookoutConnectACS/results.txt" # macOS path
$resultsFile = "C:\Users\userA\Documents\PowerShell\LookoutConnectACS/results.txt" # Windows 11 path

# Define the ACS base URL and credentials. REPLACE with your own credentials.
$acsBaseUrl = "https://localhost:29204/Acs/Api/TriggerFacade/ActivateDeactivateTrigger"
$acsUsername = "userA"
$acsPassword = "passwordA"
# Define the ACS trigger parameters
$acsParams = @{
    triggerName = "WildfireDetection"
    deactivateAfterSeconds = "5"
}
# Convert ACS credentials to Base64
$acsBase64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $acsUsername, $acsPassword)))
# Create headers including Basic Auth
$acsHeaders = @{
    Authorization = "Basic $acsBase64AuthInfo"
}

# record the start time of the iteration
$startTime = Get-Date

# Save results to results.txt
Set-Content -Path $resultsFile -Value "LookOut Connect Results"
Add-Content -Path $resultsFile -Value "-----------------------"

# Initialize an array to store capture times
$captureTimes = @()

# Initialize a variable to store number of successful process
$successTime = 0

# Repeat the process 10 times
for ($i = 1; $i -le $Iteration; $i++) {
    
    # Initialize a variable to track if Capture Snapshot is successful
    $captureSnapshot = $true

    # Get Start timing
    $getStartTime = Get-Date

    # Step 1: Capture the JPEG snapshot from the AXIS camera
    try {
        Invoke-WebRequest -Uri $cameraUrl -Credential (New-Object System.Management.Automation.PSCredential($username, (ConvertTo-SecureString $password -AsPlainText -Force))) -OutFile $outputFile -AllowUnencryptedAuthentication -ConnectionTimeoutSeconds 15 -Headers $header
    }
    catch [System.Net.WebException],[System.IO.IOException] {
        $captureSnapshot = $false
        Write-Error "Unable to capture JPEF snapshot from the camera."
    }
    catch {
        $captureSnapshot = $false
        Write-Error "An error occurred that could not be resolved."
    }

    # Get End timing
    $getEndTime = Get-Date

    # PostStart timing
    $postStartTime = Get-Date

    # Step 2: Send the captured image to LookOut Camera Endpoint via HTTPS POST
    # provide that the successful capture snapshot in the previous step 
    if ($captureSnapshot)
    {
        $response = Invoke-RestMethod -Uri $apiUrl -Method Post -InFile $outputFile -ContentType "image/jpeg"
        if ($response) 
        {
            $successTime = $successTime + 1
            $postSuccess = $True
        }
        else {
            $postSuccess = $False
        }
    }
    else {
        $postSuccess = $False
    }

    # check if the LookOut Wildfire Detection SaaS reply contains any bounding box
    if ($detection = $response | Out-String | Select-String -Pattern 'score' -Quiet)
    {
        # Write-Host $detection
        # Send the HTTPS request to ACS
        try {
            $acsResponse = Invoke-WebRequest -Uri $acsBaseUrl -Headers $acsHeaders -Method Post -Body ($acsParams | ConvertTo-Json) -ContentType "application/json" -SkipCertificateCheck
            # Write-Host "Request successful. Status Code: $($acsResponse.StatusCode)"
        }
        catch {
            Write-Host "An error occurred: $_"
            Write-Host "Error details: $($_.Exception.Message)"
        }
    }

    # Post End timing
    $postEndTime = Get-Date

    # Calculate elapsed time in milliseconds
    $getElapsedTime = ($getEndTime - $getStartTime).TotalMilliseconds
    $postElapsedTime = ($postEndTime - $postStartTime).TotalMilliseconds
    $captureTimes += $postElapsedTime
    $postElapsedTimeSecond = [math]::Round($postElapsedTime / 1000,2)

    # sleep time before the next iteration
    if (($sleepTime = [math]::Round(($WaitTime - $getElapsedTime / 1000 - $postElapsedTime / 1000),2)) -lt 0)
    {
        $sleepTime = 0
    }

    # Output response for verification (optional)
    if ($ListResults)
    {
        $postResult = "$(Get-Date) Iteration $i : HTTP Post success is $postSuccess, took $postElapsedTimeSecond seconds, wait $sleepTime more seconds"
        # Write-Host $postResult
        Add-Content -Path $resultsFile -Value $postResult
    }

    Start-Sleep -Seconds $sleepTime
}

# Calculate statistics
$averageTime = [math]::Round((($captureTimes | Measure-Object -Average).Average / 1000), 2)
$maxTime = [math]::Round((($captureTimes | Measure-Object -Maximum).Maximum / 1000), 2)
$minTime = [math]::Round((($captureTimes | Measure-Object -Minimum).Minimum / 1000), 2)

# record the end time of the iteration
$endTime = Get-Date

# Prepare results string
$resultsString = @"

Summary:
--------
Iteration start time: $startTime
Iteration end time: $endTime

Number of Iteration: $Iteration
Number of Successful Processing: $successTime
Detection interval (seconds): $WaitTime


LookOut Processing Times:
-------------------------
Average Time: $averageTime ms
Maximum Time: $maxTime ms
Minimum Time: $minTime ms
"@

# Save results to results.txt
#Set-Content -Path $resultsFile -Value $resultsString
Add-Content -Path $resultsFile -Value $resultsString

# Output results to console for verification
# Write-Host $resultsString
