#Requires -Version 5.0

<#
.SYNOPSIS
Automatically backups all remote GitHub repositories.

.DESCRIPTION
This script automatically backups all remote GitHub repositories of a user or an organisation to a local directory.

.PARAMETER userName
Specifies the GitHub user name.

.PARAMETER userSecret
Specifies the password or personal access token of the GitHub user.

.PARAMETER organisationName
Specifies the optional GitHub organisation name.

.PARAMETER backupDirectory
Overrides the default backup directory.

.EXAMPLE
.\backup_github_repositories.ps1 -userName "user" -userSecret "secret"

.EXAMPLE
.\backup_github_repositories.ps1 -userName "user" -userSecret "secret" -organisationName "organisation"

.EXAMPLE
.\backup_github_repositories.ps1 -backupDirectory "C:\myBackupDirectory"
#>

[CmdletBinding(
    DefaultParameterSetName = 'SecureSecret'
)]
Param (

    [Parameter(
        Mandatory=$True,
        HelpMessage="The name of a GitHub user that has access to the GitHub API."
    )]
    [string]$username,

    [Parameter(
        Mandatory=$True,
        HelpMessage="The password or personal access token of the GitHub user.",
        ParameterSetName = 'SecureSecret'
    )]
    [Security.SecureString]${user password or personal access token},
    [Parameter(
        Mandatory = $True,
        ParameterSetName = 'PlainTextSecret'
    )]
    [string]$userSecret,

    [string]$organisationName,

    [string]$backupDirectory
)

# Consolidate the user secret, either from the argument or the prompt, in a secure string format.
if ($userSecret) {
    $secureStringUserSecret = $userSecret | ConvertTo-SecureString -AsPlainText -Force
} else {
    $secureStringUserSecret = ${user password or personal access token}
}

# Convert the secure user secret string into a plain text representation.
$plainTextUserSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureStringUserSecret)
)

# Default the backup directory to './YYYY-MM-DD'. This can
# not be done in the Param section because $PSScriptRoot
# will not be resolved if this script gets invoked from cmd.
if (!$backupDirectory) {
    $backupDirectory = $(Join-Path -Path "$PSScriptRoot" -ChildPath $(Get-Date -UFormat "%Y-%m-%d"))
}

# Log a message to the commandline.
function Write-Message([string] $message, [string] $color = 'Yellow') {

    Write-Host "${message}" -foregroundcolor $color
}

#
# Clone a remote GitHub repository into a local directory.
#
# @see https://git-scm.com/docs/git-clone#git-clone---mirror
#
function Backup-GitHubRepository([string] $fullName, [string] $directory) {

    Write-Message "Starting backup of https://github.com/${fullName} to ${directory}..." 'DarkYellow'

    git clone --mirror "git@github.com:${fullName}.git" "${directory}"
}

#
# Calculate the total repositories size in megabytes based on GitHubs 'size' property.
#
function Get-TotalRepositoriesSizeInMegabytes([object] $repositories) {

    $totalSizeInKilobytes = 0
    ForEach ($repository in $repositories) {
        $totalSizeInKilobytes += $repository.size
    }

    $([math]::Round($totalSizeInKilobytes/1024))
}


# Measure the execution time of the backup script.
$stopwatch = [System.Diagnostics.Stopwatch]::startNew()

# Use TLS v1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

#
# Use different API endpoints for user and organisation repositories.
#
# @see https://developer.github.com/v3/repos/#list-organization-repositories
# @see https://developer.github.com/v3/repos/#list-your-repositories
#
if($organisationName) {

    $gitHubRepositoriesUrl = "https://api.github.com/orgs/${organisationName}/repos?type=all&per_page=100&page=1"

} else {

    $gitHubRepositoriesUrl = "https://api.github.com/user/repos?affiliation=owner&per_page=100&page=1"
}

#
# Compose a Basic Authentication request header.
#
# @see https://developer.github.com/v3/auth/#basic-authentication
#
$basicAuthenticationCredentials = "${username}:${plainTextUserSecret}"
$encodedBasicAuthenticationCredentials = [System.Convert]::ToBase64String(
    [System.Text.Encoding]::ASCII.GetBytes($basicAuthenticationCredentials)
)
$requestHeaders = @{
    Authorization = "Basic $encodedBasicAuthenticationCredentials"
}

# Request the GitHub API to get all repositories of a user or an organisation.
Write-Message "Requesting '${gitHubRepositoriesUrl}'..."
$repositories = Invoke-WebRequest -Uri $gitHubRepositoriesUrl -Headers $requestHeaders | `
                Select-Object -ExpandProperty Content | `
                ConvertFrom-Json

# Print a userfriendly message what will happen next.
$totalSizeInMegabytes = Get-TotalRepositoriesSizeInMegabytes -repositories $repositories
Write-Message "Cloning $($repositories.Count) repositories (~${totalSizeInMegabytes} MB) into '${backupDirectory}'..."

# Clone each repository into the backup directory.
ForEach ($repository in $repositories) {

    Backup-GitHubRepository -FullName $repository.full_name `
                            -Directory $(Join-Path -Path $backupDirectory -ChildPath $repository.name)
}

$stopwatch.Stop()
$durationInSeconds = $stopwatch.Elapsed.Seconds
Write-Message "Successfully finished the backup in ${durationInSeconds} seconds..."
