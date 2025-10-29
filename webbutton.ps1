param(
  [int]$Port = 8080,
  [string]$ScriptPath = "C:\Program Files (x86)\Steam\steamapps\common\Arma Reforger Server\launch.ps1",
  [string]$Bind = $( "http://+:{0}/" -f $Port )
)

Add-Type -AssemblyName System.Net.HttpListener
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($Bind)
$listener.Start()
Write-Host "Listening at $Bind  (Ctrl+C to stop)"

# --- Simple HTML UI ---
$IndexHtml = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Arma Reforger – Launch</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    body{font-family:system-ui,-apple-system,Segoe UI,Arial;display:flex;min-height:100vh;align-items:center;justify-content:center;background:#0f172a;color:#e2e8f0}
    .card{background:#111827;padding:24px;border-radius:14px;box-shadow:0 10px 30px rgba(0,0,0,.3);text-align:center;max-width:420px}
    button{font-size:16px;padding:12px 18px;border-radius:10px;border:0;cursor:pointer}
    .run{background:#10b981;color:#03201a}
    .run:disabled{opacity:.6;cursor:not-allowed}
    .log{font-family:ui-monospace,Consolas,monospace;margin-top:16px;font-size:14px;white-space:pre-wrap}
  </style>
</head>
<body>
  <div class="card">
    <h2>Arma Reforger Server</h2>
    <p>Click to run the server start script.</p>
    <button class="run" id="runBtn">Run launch.ps1</button>
    <div class="log" id="log"></div>
  </div>
<script>
  const btn = document.getElementById('runBtn');
  const log = document.getElementById('log');
  btn.addEventListener('click', async () => {
    btn.disabled = true;
    log.textContent = 'Starting...';
    try {
      const res = await fetch('/run', { method: 'POST' });
      const data = await res.json();
      if (data.status === 'ok') {
        log.textContent = `Started. PID: ${data.pid}`;
      } else {
        log.textContent = 'Error: ' + (data.error || 'unknown');
      }
    } catch (e) {
      log.textContent = 'Request failed: ' + e;
    } finally {
      btn.disabled = false;
    }
  });
</script>
</body>
</html>
"@

function Write-TextResponse {
  param($Context, [string]$Text, [string]$ContentType = "text/html; charset=utf-8", [int]$StatusCode = 200)
  $resp = $Context.Response
  $resp.StatusCode = $StatusCode
  $buf = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $resp.ContentType = $ContentType
  $resp.ContentLength64 = $buf.Length
  $resp.OutputStream.Write($buf, 0, $buf.Length)
  $resp.OutputStream.Close()
}

function Write-Json {
  param($Context, $Obj, [int]$StatusCode = 200)
  Write-TextResponse -Context $Context -Text ($Obj | ConvertTo-Json -Compress) -ContentType "application/json" -StatusCode $StatusCode
}

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    switch -Regex ($req.HttpMethod + " " + $req.Url.AbsolutePath) {
      '^GET /$' {
        Write-TextResponse -Context $ctx -Text $IndexHtml
      }
      '^POST /run$' {
        try {
          if (-not (Test-Path -LiteralPath $ScriptPath)) {
            Write-Json $ctx @{ status="error"; error="Script not found"; path=$ScriptPath } 500
            break
          }
          $p = Start-Process -FilePath "powershell.exe" `
                -ArgumentList "-ExecutionPolicy Bypass -File `"$ScriptPath`"" `
                -WindowStyle Hidden -PassThru
          Write-Json $ctx @{ status="ok"; pid=$p.Id }
        } catch {
          Write-Json $ctx @{ status="error"; error=$_.Exception.Message } 500
        }
      }
      default {
        Write-TextResponse -Context $ctx -Text "Not found" -ContentType "text/plain" -StatusCode 404
      }
    }
  }
} finally {
  $listener.Stop()
  $listener.Close()
}
