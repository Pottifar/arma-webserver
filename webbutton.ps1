param(
  [int]$Port = 8080,
  [string]$ScriptPath = "C:\Program Files (x86)\Steam\steamapps\common\Arma Reforger Server\launch.ps1",
  [string]$BindPrefix = $( "http://+:{0}/" -f $Port )
)

# No Add-Type needed; HttpListener is available by default.
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($BindPrefix)
$listener.Start()
Write-Host "Listening at $BindPrefix  (Ctrl+C to stop)"

$IndexHtml = @"
<!doctype html><meta charset="utf-8">
<title>Arma Reforger – Launch</title>
<meta name=viewport content="width=device-width,initial-scale=1">
<style>body{font-family:system-ui;display:flex;min-height:100vh;align-items:center;justify-content:center;background:#0f172a;color:#e2e8f0}.card{background:#111827;padding:24px;border-radius:14px;box-shadow:0 10px 30px rgba(0,0,0,.3);text-align:center;max-width:420px}button{font-size:16px;padding:12px 18px;border-radius:10px;border:0;cursor:pointer}.run{background:#10b981;color:#03201a}.run:disabled{opacity:.6;cursor:not-allowed}.log{font-family:ui-monospace,Consolas,monospace;margin-top:16px;font-size:14px;white-space:pre-wrap}</style>
<div class=card>
  <h2>Arma Reforger Server</h2>
  <p>Click to run the server start script.</p>
  <button class="run" id=runBtn>Run launch.ps1</button>
  <div class=log id=log></div>
</div>
<script>
const btn=document.getElementById('runBtn'),log=document.getElementById('log');
btn.onclick=async()=>{btn.disabled=true;log.textContent='Starting...';
  try{const r=await fetch('/run',{method:'POST'});const j=await r.json();
       log.textContent=j.status==='ok'?`Started. PID: ${j.pid}`:`Error: ${j.error||'unknown'}`}
  catch(e){log.textContent='Request failed: '+e} finally{btn.disabled=false}};
</script>
"@

function Send-Bytes($ctx, [byte[]]$bytes, $contentType='text/html; charset=utf-8', $status=200) {
  $resp = $ctx.Response
  $resp.StatusCode = $status
  $resp.ContentType = $contentType
  $resp.ContentLength64 = $bytes.Length
  $resp.OutputStream.Write($bytes,0,$bytes.Length)
  $resp.OutputStream.Close()
}
function Send-Text($ctx, [string]$text, $type='text/html; charset=utf-8', $status=200){
  Send-Bytes $ctx ([System.Text.Encoding]::UTF8.GetBytes($text)) $type $status
}
function Send-Json($ctx, $obj, $status=200){
  Send-Text $ctx ($obj | ConvertTo-Json -Compress) 'application/json' $status
}

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    switch -Regex ($req.HttpMethod + " " + $req.Url.AbsolutePath) {
      '^GET /$' { Send-Text $ctx $IndexHtml }
      '^POST /run$' {
        try {
          if (-not (Test-Path -LiteralPath $ScriptPath)) {
            Send-Json $ctx @{status='error'; error='Script not found'; path=$ScriptPath} 500
            continue
          }
          $p = Start-Process -FilePath "powershell.exe" `
               -ArgumentList "-ExecutionPolicy Bypass -File `"$ScriptPath`"" `
               -WindowStyle Hidden -PassThru
          Send-Json $ctx @{status='ok'; pid=$p.Id}
        } catch {
          Send-Json $ctx @{status='error'; error=$_.Exception.Message} 500
        }
      }
      default { Send-Text $ctx "Not found" 'text/plain' 404 }
    }
  }
} finally {
  $listener.Stop(); $listener.Close()
}
