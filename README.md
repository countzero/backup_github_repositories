# Backup all git repositories from GitHub
A PowerShell script that automatically backups all GitHub repositories of a user or an organisation to a local directory.

## Installation
Download and unpack the [latest release](https://github.com/countzero/backup_github_repositories/releases/latest) to your machine.

## Usage
Open a PowerShell console at the location of the unpacked release and execute the [./backup_github_repositories.ps1](https://github.com/countzero/backup_github_repositories/blob/master/backup_github_repositories.ps1).

## Examples

### Backup all git repositories of a user
Execute the following to backup all git repositories of a GitHub user into the subdirectory `./YYYY-MM-DD/`.
```PowerShell
.\backup_github_repositories.ps1 -userName "user" -userSecret "password"
```

### Backup all git repositores of a organisation
Execute the following to backup all git repositories of a GitHub organisation into the subdirectory `./YYYY-MM-DD/`.
```PowerShell
.\backup_github_repositories.ps1 -userName "user" -userSecret "password" -organisationName "organisation"
```

### Backup all git repositories of a user into a specific directory
Execute the following to backup all git repositories of a GitHub user into the directory `C:\myBackupDirectory` and let the script prompt for the user secret.
```PowerShell
.\backup_github_repositories.ps1 -userName "user" -backupDirectory "C:\myBackupDirectory"
```

### Get detailed help
Execute the following command to get detailed help.
```PowerShell
Get-Help .\backup_github_repositories.ps1 -detailed
```
