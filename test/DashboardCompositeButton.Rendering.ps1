param([string]$Source,[string]$OutputDirectory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($Source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors | Out-String)}
$fn=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Set-DashboardCompositeButtonAccessibility'},$true)
if(-not $fn){throw 'Missing composite accessibility function'}
. ([scriptblock]::Create($fn.Extent.Text))
New-Item -ItemType Directory -Path $OutputDirectory -ErrorAction Stop | Out-Null
$results=@()
foreach($culture in @('vi-VN','en-US')){
 foreach($width in @(226,410)){
  $title=if($culture -eq 'vi-VN'){'Phần mềm & dấu hiệu can thiệp'}else{'Software inventory and signs of tampering'}
  $form=New-Object Windows.Forms.Form
  $form.ShowInTaskbar=$false;$form.Opacity=0;$form.ClientSize=New-Object Drawing.Size(450,130)
  $button=New-Object Windows.Forms.Button
  $button.Size=New-Object Drawing.Size($width,86)
  $button.FlatStyle='Flat';$button.FlatAppearance.BorderSize=0
  $button.BackColor=[Drawing.Color]::FromArgb(244,247,251);$button.ForeColor=[Drawing.Color]::Black
  $button.UseVisualStyleBackColor=$false;$button.Padding=New-Object Windows.Forms.Padding(12,0,10,0)
  $button.ImageAlign='MiddleLeft';$button.Font=New-Object Drawing.Font('Segoe UI',10)
  $icon=New-Object Drawing.Bitmap(44,32)
  $g=[Drawing.Graphics]::FromImage($icon);$g.Clear([Drawing.Color]::Transparent);$g.FillRectangle([Drawing.Brushes]::RoyalBlue,0,0,32,32);$g.Dispose()
  $button.Image=$icon
  Set-DashboardCompositeButtonAccessibility -Button $button -AccessibleText $title
  $label=New-Object Windows.Forms.Label
  $label.Text=$title;$label.Location=New-Object Drawing.Point(60,4);$label.Size=New-Object Drawing.Size(($width-64),70)
  $label.BackColor=[Drawing.Color]::Transparent;$label.ForeColor=[Drawing.Color]::Black
  $button.Controls.Add($label);$form.Controls.Add($button)
  try{
   $form.Show();[Windows.Forms.Application]::DoEvents()
   $bitmap=New-Object Drawing.Bitmap($width,86)
   $button.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$width,86)))
   $unexpected=0
   for($x=4;$x -lt 52;$x++){for($y=4;$y -lt 82;$y++){
    if($x -ge 10 -and $x -le 46 -and $y -ge 25 -and $y -le 61){continue}
    $p=$bitmap.GetPixel($x,$y)
    if($p.R -lt 180 -and $p.G -lt 180 -and $p.B -lt 180){$unexpected++}
   }}
   $iconPreserved=($bitmap.GetPixel(24,43).ToArgb() -eq [Drawing.Color]::RoyalBlue.ToArgb())
   $semantic=($button.Text -ceq $title -and $button.AccessibilityObject.Name -ceq $title)
   $file=Join-Path $OutputDirectory ($culture+'-'+$width+'.png');$bitmap.Save($file,[Drawing.Imaging.ImageFormat]::Png);$bitmap.Dispose()
   $results+= [pscustomobject]@{Culture=$culture;Width=$width;UnwantedTextPixels=$unexpected;IconPreserved=$iconPreserved;SemanticNamePreserved=$semantic;Passed=($unexpected -eq 0 -and $iconPreserved -and $semantic)}
  }finally{$form.Dispose();$icon.Dispose()}
 }
}
$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'result.json') -Encoding UTF8
$results | ConvertTo-Json -Compress
if(@($results | Where-Object {-not $_.Passed}).Count){exit 1}
exit 0
