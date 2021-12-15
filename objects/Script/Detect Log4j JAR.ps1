#Create custom event log
#------------------------------------------------------------
function Create-CustomEventLog {
    param ($logname)
    if (!(Get-EventLog -List | Where-Object {$_.LogDisplayName -eq $logname})) {
        New-EventLog -LogName $logname -Source $logname
        Limit-EventLog -LogName $logname -OverflowAction OverwriteAsNeeded -MaximumSize 20MB
        Write-EventLog -LogName $logname -Source $logname -Message "Event log created. When writing to this event log, use the source: $logname" -EventId 0 -EntryType Information
    }
}

$logname = 'Corp'
Create-CustomEventLog $logname     #Creates Corp Eventlog if it doesn't exist.

#Eventlog Source
$Source = "Detect-Log4ShellJAR"
New-EventLog -LogName $logname -Source $Source

# CVE-2021-44228-Log4Shell-Hashes sha256sums from https://github.com/mubix/CVE-2021-44228-Log4Shell-Hashes
$hashes = @('bf4f41403280c1b115650d470f9b260a5c9042c04d9bcc2a6ca504a66379b2d6',
'58e9f72081efff9bdaabd82e3b3efe5b1b9f1666cefe28f429ad7176a6d770ae',
'ed285ad5ac6a8cf13461d6c2874fdcd3bf67002844831f66e21c2d0adda43fa4',
'dbf88c623cc2ad99d82fa4c575fb105e2083465a47b84d64e2e1a63e183c274e',
'a38ddff1e797adb39a08876932bc2538d771ff7db23885fb883fec526aff4fc8',
'7d86841489afd1097576a649094ae1efb79b3147cd162ba019861dfad4e9573b',
'4bfb0d5022dc499908da4597f3e19f9f64d3cc98ce756a2249c72179d3d75c47',
'473f15c04122dad810c919b2f3484d46560fd2dd4573f6695d387195816b02a6',
'b3fae4f84d4303cdbad4696554b4e8d2381ad3faf6e0c3c8d2ce60a4388caa02',
'dcde6033b205433d6e9855c93740f798951fa3a3f252035a768d9f356fde806d',
'85338f694c844c8b66d8a1b981bcf38627f95579209b2662182a009d849e1a4c',
'db3906edad6009d1886ec1e2a198249b6d99820a3575f8ec80c6ce57f08d521a',
'ec411a34fee49692f196e4dc0a905b25d0667825904862fdba153df5e53183e0',
'a00a54e3fb8cb83fab38f8714f240ecc13ab9c492584aa571aec5fc71b48732d',
'c584d1000591efa391386264e0d43ec35f4dbb146cad9390f73358d9c84ee78d',
'8bdb662843c1f4b120fb4c25a5636008085900cdf9947b1dadb9b672ea6134dc',
'c830cde8f929c35dad42cbdb6b28447df69ceffe99937bf420d32424df4d076a',
'6ae3b0cb657e051f97835a6432c2b0f50a651b36b6d4af395bbe9060bb4ef4b2',
'535e19bf14d8c76ec00a7e8490287ca2e2597cae2de5b8f1f65eb81ef1c2a4c6',
'42de36e61d454afff5e50e6930961c85b55d681e23931efd248fd9b9b9297239',
'4f53e4d52efcccdc446017426c15001bb0fe444c7a6cdc9966f8741cf210d997',
'df00277045338ceaa6f70a7b8eee178710b3ba51eac28c1142ec802157492de6',
'28433734bd9e3121e0a0b78238d5131837b9dbe26f1a930bc872bad44e68e44e',
'cf65f0d33640f2cd0a0b06dd86a5c6353938ccb25f4ffd14116b4884181e0392',
'5bb84e110d5f18cee47021a024d358227612dd6dac7b97fa781f85c6ad3ccee4',
'ccf02bb919e1a44b13b366ea1b203f98772650475f2a06e9fac4b3c957a7c3fa',
'815a73e20e90a413662eefe8594414684df3d5723edcd76070e1a5aee864616e',
'10ef331115cbbd18b5be3f3761e046523f9c95c103484082b18e67a7c36e570c',
'dc815be299f81c180aa8d2924f1b015f2c46686e866bc410e72de75f7cd41aae',
'9275f5d57709e2204900d3dae2727f5932f85d3813ad31c9d351def03dd3d03d',
'f35ccc9978797a895e5bee58fa8c3b7ad6d5ee55386e9e532f141ee8ed2e937d',
'5256517e6237b888c65c8691f29219b6658d800c23e81d5167c4a8bbd2a0daa3',
'd4485176aea67cc85f5ccc45bb66166f8bfc715ae4a695f0d870a1f8d848cc3d',
'3fcc4c1f2f806acfc395144c98b8ba2a80fe1bf5e3ad3397588bbd2610a37100',
'057a48fe378586b6913d29b4b10162b4b5045277f1be66b7a01fb7e30bd05ef3',
'5dbd6bb2381bf54563ea15bc9fbb6d7094eaf7184e6975c50f8996f77bfc3f2c',
'c39b0ea14e7766440c59e5ae5f48adee038d9b1c7a1375b376e966ca12c22cd3',
'6f38a25482d82cd118c4255f25b9d78d96821d22bab498cdce9cda7a563ca992',
'54962835992e303928aa909730ce3a50e311068c0960c708e82ab76701db5e6b',
'e5e9b0f8d72f4e7b9022b7a83c673334d7967981191d2d98f9c57dc97b4caae1',
'68d793940c28ddff6670be703690dfdf9e77315970c42c4af40ca7261a8570fa',
'9da0f5ca7c8eab693d090ae759275b9db4ca5acdbcfe4a63d3871e0b17367463',
'006fc6623fbb961084243cfc327c885f3c57f2eba8ee05fbc4e93e5358778c85')

$drives = Get-CimInstance Win32_LogicalDisk | Where-Object DriveType -eq 3 | Select -ExpandProperty DeviceID
$i = 0
Foreach ($drive in $drives) {
    $jars = Get-ChildItem -Path "$drive\" -Filter log4j*.jar -Recurse -ErrorAction SilentlyContinue

    Foreach ($jar in $jars){
        $params = @{
            LogName = $logname
            Source  = $Source
            Message = ""
            EventID = ''
            EntryType = ''
        }

        $file = Get-FileHash -Path $jar.Fullname
        if ($file.Hash -in $hashes ){
            $params.Message = "Found vulnerable log4j library!
File: $($jar.FullName)
Hash: $($file.Hash)

For more info on CVE-2021-44228, see https://www.huntress.com/blog/rapid-response-critical-rce-vulnerability-is-affecting-java"
            $params.EventID = '200'
            $params.EntryType = 'Warning'

            Write-EventLog @params
            $i++    #increase $i to instruct CM that vulnerability found
        }
        Else {
        $params.Message = "Found log4j library, but is not considered a vulnerable version.
File: $($jar.FullName)
Hash: $($file.Hash)

For more info on CVE-2021-44228, see: https://www.huntress.com/blog/rapid-response-critical-rce-vulnerability-is-affecting-java"
                $params.EventID = '100'
                $params.EntryType = 'Information'
            
            Write-EventLog @params
        }
    }
}

If ($i -ge 1){ "Vulnerable" }
Else { "Compliant" }