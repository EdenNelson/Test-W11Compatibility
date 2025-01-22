<#
.SYNOPSIS
    This script intended to run within a ConfigMgr Task Sequnce, it checks the compatibility of a system with Windows 11, including UEFI, Secure Boot, TPM, and processor compatibility.

.DESCRIPTION
    The script performs the following tasks:
    - Sets up Task Sequence Environment and Progress UI.
    - Retrieves Task Sequence Variables.
    - Checks if the system is a Virtual Machine and performs compatibility checks accordingly.
    - For physical machines, it checks the processor compatibility against the Windows 11 supported processor lists from Microsoft.
    - Verifies UEFI, Secure Boot, and TPM 2.0 compatibility.
    - Displays appropriate messages and error dialogs based on the compatibility checks.
    
.FUNCTION Get-TableDataFromWebRequest
    Retrieves table data from a web request.
    - Modififed from the original function by Lee Holmes.
    - @LeeHolmes
    - https://www.leeholmes.com/extracting-tables-from-powershells-invoke-webrequest/

.NOTES
    Author: Eden Nelson [EdenNelson]
    Version: 2025.01.21.0
.EXAMPLE
    .\Test-Win11Compat.ps1
    Runs the script to check Windows 11 compatibility on the current system.
.REQUIRES
    - PowerShell 5.1 or later
    - MDT integrated Task Sequence or Similar to provide Task Sequence Environment variables
    - WinPE 10 or later
    - Internet access to retrieve the Windows 11 supported processor lists from Microsoft
#>
[CmdletBinding()]
param(
    [ValidateSet("Silent", "GUIHard", "GUISoft")]
    [string]$ErrorStopType = "Silent"
)

# Task Sequence Progress UI COM Object Setup
$TSProgressUi = New-Object -ComObject Microsoft.SMS.TSProgressUI
# Task Sequence Environment COM Object Setup
$TSEnv = New-Object -COMObject Microsoft.SMS.TSEnvironment
# Task Sequence Variables
$BootedUEFI = $TSEnv.Value("_SMSTSBootUEFI")
$SecureBoot = $TSEnv.Value("_TSSecureBoot")
$TPMisActive = $TSEnv.Value("TPMIsActive")
$TPMisEnabled = $TSEnv.Value("TPMIsEnabled")
$TPMIsV2 = $TSEnv.Value("TPMIsV2")
$IsVM = $TSEnv.Value("IsVM")
[int]$Memory = $TSEnv.Value("Memory")

# Check if the memory is greater than 4GB
if ($Memory -ge 4096) {
    Write-Verbose -Message "Memory is $Memory MB, which is greater than 4GB"
    $MemoryCompatible = $true
}
else {
    Write-Verbose -Message "Memory is $Memory MB, which is less than 4GB"
    $MemoryCompatible = $false
}

# CPU Compatibility data
# Processor Manufacturer list
$ManufacturerList = @("Intel", "AMD", "Qualcomm")
# This script will check if the processor in the system is compatible with Windows 11 22H2/23H2

# Switch based on the Windows 11 version Default is 23H2
$URIW11IntelProcs = "https://learn.microsoft.com/en-us/windows-hardware/design/minimum/supported/windows-11-23h2-supported-intel-processors"
$URIW11AMDProcs = "https://learn.microsoft.com/en-us/windows-hardware/design/minimum/supported/windows-11-23h2-supported-amd-processors"
$URIW11QualcommProcs = "https://learn.microsoft.com/en-us/windows-hardware/design/minimum/supported/windows-11-23h2-supported-qualcomm-processors"



# Get the processor information table from the LIVE Microsoft website
function Get-TableDataFromWebRequest {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.PowerShell.Commands.HtmlWebResponseObject] $WebRequest,
      
        [Parameter(Mandatory = $true)]
        [int] $TableNumber
    )

    # Extract the tables out of the web request
    $tables = @($WebRequest.ParsedHtml.getElementsByTagName("TABLE"))
    $table = $tables[$TableNumber]
    $titles = @()
    $rows = @($table.Rows)

    # Go through all of the rows in the table
    foreach ($row in $rows) {
        $cells = @($row.Cells)
       
        # If we've found a table header, remember its titles
        if ($cells[0].tagName -eq "TH") {
            $titles = @($cells | % { ("" + $_.InnerText).Trim() })
            continue
        }

        # If we haven't found any table headers, make up names "P1", "P2", etc.
        if (-not $titles) {
            $titles = @(1..($cells.Count + 2) | % { "P$_" })
        }

        # Now go through the cells in the the row. For each, try to find the
        # title that represents that column and create a hashtable mapping those
        # titles to content
        $resultObject = [Ordered] @{ }
        for ($counter = 0; $counter -lt $cells.Count; $counter++) {
            $title = $titles[$counter]
            if (-not $title) { continue }  

            $resultObject[$title] = ("" + $cells[$counter].InnerText).Trim()
        }

        # And finally cast that hashtable to a PSCustomObject
        [PSCustomObject] $resultObject
    }
}

function Format-CpuName {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string]$CPUName
    )

    # Remove unnecessary characters
    $CleanCpuName = $CpuName -replace "\(R\)", "" # Remove (R) from the string
    $CleanCpuName = $CleanCpuName -replace "\(TM\)", "" # Remove (TM) from the string
    $CleanCpuName = $CleanCpuName -replace " CPU", "" # Remove CPU from the string
    $CleanCpuName = $CleanCpuName -replace " @ \d+\.\d+GHz", "" # Remove the clock speed from the string
    $CleanCpuName = $CleanCpuName -replace "^\d+th Gen ", "" # Remove the generation from the string from the beginning of the string
    $CleanCpuName = $CleanCpuName -replace " \d+-Core Processor$", "" # Remove n-Core Processor from the end of the string

    # Extract Manufacturer using regex and check for known manufacturers Intel, AMD, Qualcomm. If the Manufacturer is not found, set it to $null. If the Manufacturer is Intel, AMD, or Qualcomm, remove the Manufacturer from the string.
    if ($CleanCpuName -match "Intel|AMD|Qualcomm") { 
        $Manufacturer = $Matches[0]
        $CleanCpuName = $CleanCpuName -replace "$Manufacturer ", ""
    }
    elseif ($CleanCpuName -match "Pentium|Celeron|Xeon|Core|Atom|Itanium") {
        $Manufacturer = "Intel"
    }
    else {
        $Manufacturer = $null
    }

    # Extract Brand and Model using regex. If the Brand and Model are not found,
    if ($CleanCpuName -match "^(?<Brand>\w+)\s+(?<Model>.*)") {
        $Brand = $Matches['Brand']
        $Model = $Matches['Model']
    } 

    if ($Manufacturer -eq "AMD" -and $Brand -eq "Ryzen" -and $Model -match "^\d\s|^\d PRO|^Embedded\s|^Threadripper\s|^Threadripper PRO\s|^Embedded\sR2000\sSeries\s") {
        $Brand = $Brand, ' ', $matches[0] -join ''
        $Model = $Model -replace $matches[0], ''
    }
    elseif ($Manufacturer -eq "AMD" -and $Brand -eq "Athlon" -and $Model -match "^II\s") {
        $Brand = $Brand, ' ', $matches[0] -join ''
        $Model = $Model -replace $matches[0], ''
    }
    elseif ($Manufacturer -eq "Intel" -and -not $Brand -and -not $Model -and $CleanCpuName -match "^N\d+$") {
        $Brand = "N-series"
        $Model = $CleanCpuName
    }
    elseif ($Manufacturer -eq "AMD" -and -not $Brand -and -not $Model -and $CleanCpuName -match "^A\d+-\d+") {
        $Brand = "A-series"
        $Model = $CleanCpuName
    }

    # If the Manufacturer, Brand, or Model is not found, write a warning and return $null.
    if (-not $Manufacturer -or -not $Brand -or -not $Model) {
        Write-Warning -Message "Could not parse CPU name: $CpuName"
        return $null
    }
    else { 
        [PSCustomObject]@{
            Manufacturer = $Manufacturer
            Brand        = $Brand
            Model        = $Model
        }
    }
}

#Main Script
# Create a hashtable with the processor information

$Processor = ((Get-CimInstance -ClassName Win32_Processor).name | Format-CpuName)

if ($IsVM -eq "True") {
    Write-Verbose -Message "This is a Virtual Machine"
    Write-Verbose -Message "Skipping most Windows 11 Compatibility checks"

    if ($BootedUEFI -and $SecureBoot -and $TPMisActive -and $TPMisEnabled -and $TPMisEnabled -and $TPMIsV2 -and $MemoryCompatible) {
        Write-Verbose -Message "VM components are compatible with Windows 11 including UEFI, Secure Boot and TPM 2.0"
    }
    else {
        Write-Verbose -Message "Not all components are compatible with Windows 11"

        Write-Verbose -Message "Booted UEFI: $BootedUEFI"
        Write-Verbose -Message "Secure Boot: $SecureBoot"
        Write-Verbose -Message "TPM is Active: $TPMisActive"
        Write-Verbose -Message "TPM is Enabled: $TPMisEnabled"
        Write-Verbose -Message "TPM is Version 2.0: $TPMIsV2"
        Write-Verbose -Message "Memory is greater than 4GB: $MemoryCompatible"

        # Close the default Task Sequence Progress dialog
        $TSProgressUi.CloseProgressDialog()
        # Show the custom error dialog
        $TSProgressUi.ShowErrorDialog($OrganizationName, $TSPackageName, $CustomTitle, $ErrorMessage, $ErrorCode, $TimeoutInSeconds, $Reboot, $TSStepName)
        Exit 1
    }

}
else {
    Write-Verbose -Message "This is a Physical Machine"
    Write-Verbose -Message "Checking All Windows 11 Compatibility"

    # Check the processor compatibility with Windows 11
    Remove-Variable -Name CompatProc -ErrorAction SilentlyContinue
    switch ($Processor.Manufacturer) {
        Intel {
            Write-Verbose -Message "Installed Processor is an Intel Processor"
            Write-Verbose -Message "Getting Intel Processor Compatibility List"
            Try {
                $WebRequest = Invoke-WebRequest -Uri $URIW11IntelProcs
                $CompatProc = (Get-TableDataFromWebRequest -WebRequest $WebRequest -TableNumber 0) -replace "Â®", '' -replace 'â', '' -replace '¢', ''
            }
            Catch {
                Write-Warning -Message "Error getting the Intel Processor Compatibility List"
                #Exit 1
            }
        }
        AMD {
            Write-Verbose -Message "Installed Processor is an AMD Processor"
            Write-Verbose -Message "Getting AMD Processor Compatibility List"
            try {
                $WebRequest = Invoke-WebRequest -Uri $URIW11AMDProcs
                $CompatProc = (Get-TableDataFromWebRequest -WebRequest $WebRequest -TableNumber 0) -replace "Â®", '' -replace 'â', '' -replace '¢', ''
            }
            Catch {
                Write-Warning -Message "Error getting the AMD Processor Compatibility List"
                #Exit 1
            }
        }
        Qualcomm {
            Write-Verbose -Message "Installed Processor is a Qualcomm Processor"
            Write-Verbose -Message "Getting Qualcomm Processor Compatibility List"
            try {
                $WebRequest = Invoke-WebRequest -Uri $URIW11QualcommProcs
                $CompatProc = (Get-TableDataFromWebRequest -WebRequest $WebRequest -TableNumber 0) -replace "Â®", '' -replace 'â', '' -replace '¢', ''
            }
            Catch {
                Write-Warning -Message "Error getting the Qualcomm Processor Compatibility List"
                Exit 1
            }
        }
        Default {
            Write-Warning -Message "Installed Processor is not an Intel, AMD or Qualcomm Processor"
            Exit 1
        }
    }
    
    # Check if the processor Manufacturer is in the static compatibility list
    Remove-Variable -Name ManufacturerIsCompatible -ErrorAction SilentlyContinue
    $Processor.Manufacturer | ForEach-Object {
        Write-Verbose -Message "Checking if the Manufacturer of Installed CPU: $($Processor.Manufacturer) is compatible with Windows 11"
        Write-Verbose -Message  "Attempting to matching with $_ from the compatibility list"
        if ($ManufacturerList -match $_) { $ManufacturerIsCompatible = $true }
    }

    # Check if the processor is in the compatibility list
    Remove-Variable -Name BrandIsCompatible -ErrorAction SilentlyContinue
    $Processor.Brand | ForEach-Object {
        Write-Verbose -Message "Checking if the Brand of Installed CPU: $($Processor.Brand) is compatible with Windows 11"
        Write-Verbose -Message  "Attempting to matching with $_ from the compatibility list"
        if ($CompatProc -match $_) { $BrandIsCompatible = $true }
    }

    # Check if the processor is in the compatibility list
    Remove-Variable -Name ModelIsCompatible -ErrorAction SilentlyContinue
    $Processor.Model | ForEach-Object {
        Write-Verbose -Message "Checking if the Model of Installed CPU: $($Processor.Model) is compatible with Windows 11"
        Write-Verbose -Message  "Attempting to matching with $_ from the compatibility list"
        if ($CompatProc -match $_) { $ModelIsCompatible = $true }
    }

    # Check if all components are compatible
    if ($ManufacturerIsCompatible -and $BrandIsCompatible -and $ModelIsCompatible -and $BootedUEFI -and $SecureBoot -and $TPMisActive -and $TPMisEnabled -and $TPMisEnabled -and $TPMIsV2 -and $MemoryCompatible) {
        Write-Verbose -Message "All components are compatible with Windows 11 including the Processor, UEFI, Secure Boot and TPM 2.0"
        exit 0
    }
    else {
        Write-Verbose -Message "Not all components are compatible with Windows 11"

        Write-Verbose -Message "processor Manufacturer: $ManufacturerIsCompatible"
        Write-Verbose -Message "processor Brand: $BrandIsCompatible"
        Write-Verbose -Message "processor Model: $ModelIsCompatible"
        Write-Verbose -Message "Booted UEFI: $BootedUEFI"
        Write-Verbose -Message "Secure Boot: $SecureBoot"
        Write-Verbose -Message "TPM is Active: $TPMisActive"
        Write-Verbose -Message "TPM is Enabled: $TPMisEnabled"
        Write-Verbose -Message "TPM is Version 2.0: $TPMIsV2"
        Write-Verbose -Message "Memory is greater than 4GB: $MemoryCompatible"

        if ($ErrorStopType -eq "GUIHard") {
            Write-Verbose -Message "GUI Hard Error Stop Type - Showing Error Dialog and stopping the Task Sequence"
            # Close the default Task Sequence Progress dialog
            $TSProgressUi.CloseProgressDialog()
            # Show the custom error dialog
            $TSProgressUi.ShowErrorDialog($OrganizationName, $TSPackageName, $CustomTitle, $ErrorMessage, $ErrorCode, $TimeoutInSeconds, $Reboot, $TSStepName)
            exit 1
        }
        elseif ($ErrorStopType -eq "GUISoft") {
            Write-Verbose -Message "GUI Soft Error Stop Type - Showing Error Dialog with option to continue the Task Sequence"
            # Close the default Task Sequence Progress dialog
            $TSProgressUi.CloseProgressDialog()
            # Show the custom error dialog
            $TSProgressUi.ShowErrorDialog($OrganizationName, $TSPackageName, $CustomTitle, $ErrorMessage, $ErrorCode, $TimeoutInSeconds, $Reboot, $TSStepName)
            exit 1
        }
        else {
            Write-Verbose -Message "Silent Error Stop Type - Exiting with error code 1 now"
            exit 1
        }
        }
    }


