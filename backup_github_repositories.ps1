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
    [string]$userName,

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
    [String]$userSecret,

    [String]$organisationName,

    [String]$backupDirectory,

    [ValidateRange(0,256)]
    [Int]$maxConcurrency=2
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
# Clone or fetch a remote GitHub repository into a local directory.
#
# @see https://git-scm.com/docs/git-clone#git-clone---mirror
#
function Backup-GitHubRepository([string] $fullName, [string] $directory) {

    Write-Message "Starting backup of https://github.com/${fullName} to ${directory}..." 'DarkYellow'

    if (Test-Path "${directory}") {

        git --git-dir="${directory}" fetch --all
        git --git-dir="${directory}" fetch --tags
        return
    }

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
if ($organisationName) {

    $gitHubRepositoriesUrl = "https://api.github.com/orgs/${organisationName}/repos?type=all&per_page=50"

} else {

    $gitHubRepositoriesUrl = "https://api.github.com/user/repos?affiliation=owner&per_page=50"
}

#
# Compose a Basic Authentication request header.
#
# @see https://developer.github.com/v3/auth/#basic-authentication
#
$basicAuthenticationCredentials = "${userName}:${plainTextUserSecret}"
$encodedBasicAuthenticationCredentials = [System.Convert]::ToBase64String(
    [System.Text.Encoding]::ASCII.GetBytes($basicAuthenticationCredentials)
)
$requestHeaders = @{
    Authorization = "Basic $encodedBasicAuthenticationCredentials"
}

# Request the paginated GitHub API to get all repositories of a user or an organisation.
$repositories = @()
$pageNumber = 0
Do {

    $pageNumber++
    $paginatedGitHubApiUri = "${gitHubRepositoriesUrl}&page=${pageNumber}"

    Write-Message "Requesting '${paginatedGitHubApiUri}'..."
    $paginatedRepositories = Invoke-WebRequest -Uri $paginatedGitHubApiUri -Headers $requestHeaders | `
                             Select-Object -ExpandProperty Content | `
                             ConvertFrom-Json

    $repositories += $paginatedRepositories

} Until ($paginatedRepositories.Count -eq 0)

# Print a userfriendly message what will happen next.
$totalSizeInMegabytes = Get-TotalRepositoriesSizeInMegabytes -repositories $repositories
Write-Message "Cloning $($repositories.Count) repositories (~${totalSizeInMegabytes} MB) into '${backupDirectory}'..."

# Clone each repository into the backup directory.
ForEach ($repository in $repositories) {

    # The repository directory is suffixed with a ".git" to indicate a bare repository.
    Backup-GitHubRepository -FullName $repository.full_name `
                            -Directory $(Join-Path -Path $backupDirectory -ChildPath "$($repository.name).git")
}

$stopwatch.Stop()
$durationInSeconds = $stopwatch.Elapsed.TotalSeconds
Write-Message "Successfully finished the backup in ${durationInSeconds} seconds..."
