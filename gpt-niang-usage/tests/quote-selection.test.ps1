param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$appDir=Split-Path $TestRoot -Parent
. (Join-Path $appDir 'runtime\quotes.ps1')
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $appDir 'runtime\color-theme.ps1'),[Text.Encoding]::UTF8)))
function Assert($Condition,[string]$Message){if(!$Condition){throw $Message}}
$root=Join-Path ([IO.Path]::GetTempPath()) ('gpt-niang-selection-'+[Guid]::NewGuid().ToString('N'))
try{
  $data=Join-Path $root 'rounds';$settings=Get-WidgetSelectionSettings $data
  Assert ($settings.preferred-eq 40 -and $settings.shown-eq 20 -and $settings.unseen-eq 40 -and $settings.includeGenerated -and $settings.coloredText) 'Agreed selection defaults'
  $library=@{base=@(1..4|ForEach-Object{[pscustomobject]@{text=('偏爱'+$_);preferred=$true;weight=1}});deleted=@()}
  Save-WidgetQuoteLibrary $data $library
  $settings.preferred=100;$settings.shown=0;$settings.unseen=0;Save-WidgetSelectionSettings $data $settings
  $displayed=@()
  foreach($i in 1..2){$line=Get-WidgetQuote $data;Register-WidgetQuoteShown $data $line;$displayed+=@($line)}
  . (Join-Path $appDir 'runtime\quotes.ps1')
  $script:widgetQuotePending=@{}
  foreach($i in 1..2){$line=Get-WidgetQuote $data;Register-WidgetQuoteShown $data $line;$displayed+=@($line)}
  Assert (@($displayed|Select-Object -Unique).Count-eq 4) 'Restart resumes a round without repeating its already displayed members'
  $history=Read-WidgetQuoteHistory $data
  $before=[IO.File]::ReadAllText((Join-Path $data 'quote-history.json'))
  $null=Get-WidgetQuote $data
  Assert ([IO.File]::ReadAllText((Join-Path $data 'quote-history.json'))-eq $before) 'Candidate selection without actual display never advances persisted progress'
  $library.base=@($library.base|Where-Object{$_.text-ne $displayed[0]})+@([pscustomobject]@{text='新增偏爱';preferred=$true;weight=1000})
  Save-WidgetQuoteLibrary $data $library
  $line=Get-WidgetQuote $data;Register-WidgetQuoteShown $data $line
  Assert ($line-ne $displayed[0]) 'Deleted entries cannot survive in a stored rotation'

  $data=Join-Path $root 'shares';$settings=Get-WidgetSelectionSettings $data
  $settings.preferred=60;$settings.shown=40;$settings.unseen=0;Save-WidgetSelectionSettings $data $settings
  Save-WidgetQuoteLibrary $data @{base=@([pscustomobject]@{text='偏爱';preferred=$true;weight=1},[pscustomobject]@{text='已展示';weight=1000});deleted=@()}
  Register-WidgetQuoteShown $data '已展示';$script:widgetQuoteRandom=[Random]::new(43)
  $preferred=0;$last='';$repeat=$false
  foreach($i in 1..200){$line=Get-WidgetQuote $data;if($line-eq '偏爱'){$preferred++};if($line-eq $last){$repeat=$true};Register-WidgetQuoteShown $data $line;$last=$line}
  Assert ($preferred-ge 100 -and $preferred-le 140) 'Class percentage remains effective despite singleton favorite and obsolete unequal item weights'
  Assert $repeat 'Shares take precedence over a global no-repeat rule'

  $data=Join-Path $root 'membership';$settings=Get-WidgetSelectionSettings $data
  $settings.preferred=0;$settings.shown=0;$settings.unseen=100;Save-WidgetSelectionSettings $data $settings
  $null=Save-WidgetQuotes $data @('未展示甲','未展示乙')
  $one=Get-WidgetQuote $data;Register-WidgetQuoteShown $data $one
  $two=Get-WidgetQuote $data;Register-WidgetQuoteShown $data $two
  Assert ($one-ne $two) 'Actual display moves a non-preferred quote out of the unseen class'
  $empty=Get-WidgetQuote $data
  Assert ($empty-like '当前配比下没有可用语录*') 'Zero-share classes never silently receive an exhausted class share'
  Register-WidgetQuoteShown $data $empty
  Assert ((Read-WidgetQuoteHistory $data).shown.Count-eq 2) 'An inventory message does not become display history or consume a round'
  $settings.shown=100;$settings.unseen=0;Save-WidgetSelectionSettings $data $settings
  Assert (@('未展示甲','未展示乙')-contains (Get-WidgetQuote $data)) 'Shown members remain available after changing shares'
  $settings.shown=80;$settings.unseen=20;Save-WidgetSelectionSettings $data $settings
  Assert (@('未展示甲','未展示乙')-contains (Get-WidgetQuote $data)) 'An empty positive-share class redistributes to a populated enabled class'
  $before=[IO.File]::ReadAllText((Join-Path $data 'quote-selection.json'));$settings.preferred=1
  $failed=$false;try{Save-WidgetSelectionSettings $data $settings}catch{$failed=$true}
  Assert ($failed -and [IO.File]::ReadAllText((Join-Path $data 'quote-selection.json'))-eq $before) 'Invalid totals leave the previous valid preference intact'

  $data=Join-Path $root 'generation';$settings=Get-WidgetSelectionSettings $data
  $settings.preferred=0;$settings.shown=0;$settings.unseen=100;Save-WidgetSelectionSettings $data $settings
  $null=Save-WidgetQuotes $data @();Write-WidgetQuoteJson (Join-Path $data 'generated-quotes.json') @{quotes=@('已有生成句')}
  Assert (!(Get-WidgetGenerationSettings $data).enabled -and (Get-WidgetQuote $data)-eq '已有生成句') 'Default-off model generation does not exclude existing generated stock'
  $settings.includeGenerated=$false;Save-WidgetSelectionSettings $data $settings
  $generation=Get-WidgetGenerationSettings $data;$generation.enabled=$true;Save-WidgetGenerationSettings $data $generation
  Assert ((Get-WidgetQuote $data)-like '语录库存为空*') 'Enabling model generation never changes explicit source visibility'
  $settings.includeGenerated=$true;Save-WidgetSelectionSettings $data $settings
  $generation.enabled=$false;Save-WidgetGenerationSettings $data $generation
  Assert ((Get-WidgetQuote $data)-eq '已有生成句') 'Disabling model generation never changes source visibility'
  $script:colorMode='original';$script:quoteInkRandom=[Random]::new(43);$colors=@{}
  foreach($i in 1..20){$null=Get-WidgetBubbleQuote $data;Assert ($script:quoteSceneInk-is [Windows.Media.SolidColorBrush] -and $script:quoteSceneInk.IsFrozen) 'Each displayed quote gets static ink';$colors[$script:quoteSceneInk.Color.ToString()]=$true}
  Assert ($colors.Count-ge 3) 'Repeated lines can use distinct colors from the widget palette'
  $script:bubbleMode='quote';$script:ui=@{QuoteText=[Windows.Controls.TextBlock]::new()};Set-WidgetQuoteSceneInk
  $brush=$script:ui.QuoteText.Foreground;Set-WidgetQuoteSceneInk
  Assert ([object]::ReferenceEquals($brush,$script:ui.QuoteText.Foreground)) 'Scene refresh does not change the chosen quote color'
  $settings.coloredText=$false;Save-WidgetSelectionSettings $data $settings;$null=Get-WidgetBubbleQuote $data
  Assert ($null-eq $script:quoteSceneInk) 'Color preference is independently editable'
  Write-Output ('PASS: persisted actual-display rotation, source/generation independence, class shares ('+$preferred+'/200 preferred), zero/empty classes, deletion, validation and static palette ink')
}finally{
  $target=[IO.Path]::GetFullPath($root);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
  if(!$target.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($target)-notlike 'gpt-niang-selection-*'){throw 'Unexpected selection test directory'}
  if([IO.Directory]::Exists($target)){Remove-Item -LiteralPath $target -Recurse -Force}
}
