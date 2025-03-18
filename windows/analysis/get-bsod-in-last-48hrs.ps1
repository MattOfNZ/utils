$startTime = (Get-Date).AddHours(-48)
Get-WinEvent -FilterHashtable @{
    LogName = 'System'
    Level = 1,2,3
    StartTime = $startTime
} | Where-Object { 
    $_.ProviderName -match 'Kernel|BugCheck|WHEA' -or 
    $_.Message -match 'blue\s*screen|bugcheck|crash|dump|stop\s*code|0x0+[0-9a-f]+' 
} | Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message | Format-List
