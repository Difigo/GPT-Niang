param([string]$TestRoot=$PSScriptRoot,[string]$PreviewDirectory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$appDir=Split-Path $TestRoot -Parent
. (Join-Path $appDir 'runtime\quotes.ps1')
$script:widgetQuotesBuiltInPath=Join-Path $appDir 'assets\quotes.json'
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $appDir 'runtime\quote-generation-ui.ps1'),[Text.Encoding]::UTF8)))
function Assert($Condition,[string]$Message){if(!$Condition){throw $Message}}
$script:dataDir=Join-Path ([IO.Path]::GetTempPath()) ('gpt-niang-quote-ui-'+[Guid]::NewGuid().ToString('N'))
$script:window=New-Object Windows.Window;$script:collapsed=$true;$script:bubbleMode='quota'
try{
  Initialize-WidgetQuoteHistory $script:dataDir
  $history=Read-WidgetQuoteHistory $script:dataDir
  Assert ($history.shown.Count-eq 0) 'Startup does not mark any quote as shown'
  $defaults=Get-WidgetGenerationSettings $script:dataDir
  Assert (!$defaults.enabled -and $defaults.batchSize-eq 43 -and $defaults.threshold-eq 20) 'Fresh install is off with agreed defaults'
  $null=Save-WidgetQuotes $script:dataDir @('原有一','原有二')
  Write-WidgetQuoteJson (Join-Path $script:dataDir 'generated-quotes.json') @{quotes=@('新台词')}
  Register-WidgetQuoteShown $script:dataDir '原有一'
  Assert ((Read-WidgetQuoteHistory $script:dataDir).shown.Count-eq 1) 'Disabled feature still records display history'
  foreach($i in 1..8){Assert ((Get-WidgetQuote $script:dataDir)-ne '新台词') 'Off excludes generated quotes'}
  Assert ((Read-WidgetQuoteHistory $script:dataDir).shown.Count-eq 1) 'Selecting a candidate alone does not mark it as shown'
  $defaults.enabled=$true;Save-WidgetGenerationSettings $script:dataDir $defaults
  $saved=[IO.File]::ReadAllText((Join-Path $script:dataDir 'quote-generation.json'))|ConvertFrom-Json
  Assert ($saved.PSObject.Properties.Name-ccontains 'batchSize') 'Settings use canonical shared JSON field names'
  Register-WidgetQuoteShown $script:dataDir '原有二'
  Assert ((Get-WidgetQuote $script:dataDir)-eq '新台词') 'History from before enable excludes previously shown originals'
  Register-WidgetQuoteShown $script:dataDir '新台词'
  Assert ((Read-WidgetQuoteHistory $script:dataDir).shown.Count-eq 3) 'Generated quote display is recorded'
  $null=Get-WidgetQuote $script:dataDir
  $key=Get-WidgetQuoteKey 'ＧＰＴ 娘 🖐️😡🤚'
  $node=(Get-Command node.exe -ErrorAction Stop).Source
  $module=[Uri](Join-Path $appDir 'runtime\quote-generation.mjs')
  $expected=& $node --input-type=module -e "const {quoteKey}=await import(process.argv[1]); console.log(quoteKey('ＧＰＴ 娘 🖐️😡🤚'));" $module.AbsoluteUri
  Assert ($LASTEXITCODE-eq 0 -and $key-eq $expected) 'Node and PowerShell share Unicode/emoji history keys'
  $script:window.Opacity=0;$script:window.Show()
  $editor=Open-QuoteGenerationSettings -CheckOnly
  Assert ($editor.FindName('Enabled').IsChecked-eq $true) 'UI restores persisted enable state'
  Assert ($editor.FindName('BatchSize').Text-eq '43') 'UI shows GPT quantity'
  $editor.FindName('Enabled').IsChecked=$false
  Assert (!(Get-WidgetGenerationSettings $script:dataDir).enabled) 'Uncheck persists off immediately without Save'
  Assert ([IO.File]::Exists((Join-Path $script:dataDir 'generated-quotes.json'))) 'Disable preserves stock'
  Assert ((Read-WidgetQuoteHistory $script:dataDir).shown.Count-eq 3) 'Disable preserves history'
  $editor.FindName('Enabled').IsChecked=$true;$editor.FindName('BatchSize').Text='0'
  $editor.FindName('Save').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  Assert (!(Get-WidgetGenerationSettings $script:dataDir).enabled) 'Invalid fields cannot enable generation'
  $editor.FindName('BatchSize').Text='43';$editor.FindName('MaxDaily').Text='4';$editor.FindName('MinIntervalMinutes').Text='15';$editor.FindName('Model').Text='my-model'
  $editor.FindName('Save').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  $settings=Get-WidgetGenerationSettings $script:dataDir
  Assert ($settings.enabled -and $settings.maxDaily-eq 4 -and $settings.minIntervalMinutes-eq 15 -and $settings.model-eq 'my-model') 'Editable model and budget persist across reload'
  if($PreviewDirectory){
    $null=[IO.Directory]::CreateDirectory($PreviewDirectory)
    $editor.Content.Measure([Windows.Size]::new(536,650));$editor.Content.Arrange([Windows.Rect]::new(0,0,536,650));$editor.Content.UpdateLayout()
    $image=[Windows.Media.Imaging.RenderTargetBitmap]::new(536,650,96,96,[Windows.Media.PixelFormats]::Pbgra32);$image.Render($editor.Content)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($image))
    $stream=[IO.File]::Create((Join-Path $PreviewDirectory 'quote-generation-settings.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
  }
  Disable-WidgetQuoteGeneration
  Assert (!(Get-WidgetGenerationSettings $script:dataDir).enabled) 'Off survives settings reload'
  Write-Output 'PASS: persistent history from first run, separate pools, unseen selection, shared Unicode keys, settings validation, default off and immediate disable'
}finally{
  if($script:generationEditor){$script:generationEditor.Close()};$script:window.Close()
  $target=[IO.Path]::GetFullPath($script:dataDir);$temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  if(!$target.StartsWith($temporary,[StringComparison]::OrdinalIgnoreCase)){throw 'Unexpected test directory'}
  if([IO.Directory]::Exists($target)){Remove-Item -LiteralPath $target -Recurse -Force}
}
