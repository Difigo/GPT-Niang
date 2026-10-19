# Selection preferences are independent of model invocation settings.
function Get-WidgetSelectionSettings([string]$DataDir) {
  $result=@{version=1;preferred=40;shown=20;unseen=40;includeGenerated=$true;coloredText=$true}
  try{
    $saved=[IO.File]::ReadAllText((Join-Path $DataDir 'quote-selection.json'),[Text.Encoding]::UTF8)|ConvertFrom-Json
    $valid=$true;$total=0
    foreach($name in @('preferred','shown','unseen')){
      $value=$saved.$name
      if(($value-isnot [int] -and $value-isnot [long]) -or $value-lt 0 -or $value-gt 100){$valid=$false;break}
      $total+=$value
    }
    if($valid -and $total-eq 100){foreach($name in @('preferred','shown','unseen')){$result[$name]=[int]$saved.$name}}
    foreach($name in @('includeGenerated','coloredText')){if($saved.$name-is [bool]){$result[$name]=$saved.$name}}
  }catch{}
  return $result
}
function Save-WidgetSelectionSettings([string]$DataDir,$Value) {
  $saved=@{version=1;includeGenerated=[bool]$Value.includeGenerated;coloredText=[bool]$Value.coloredText};$total=0
  foreach($name in @('preferred','shown','unseen')){
    $number=0
    if(![int]::TryParse([string]$Value[$name],[ref]$number) -or $number-lt 0 -or $number-gt 100){throw '每类占比须为 0–100 的整数。'}
    $saved[$name]=$number;$total+=$number
  }
  if($total-ne 100){throw '三类占比合计须为 100%。0% 表示不抽取该类。'}
  Write-WidgetQuoteJson (Join-Path $DataDir 'quote-selection.json') $saved
}
function Get-WidgetSelectionPools([string]$DataDir,$Settings,$History) {
  $rows=@((Get-WidgetQuoteSettings $DataDir).quotes)
  if($Settings.includeGenerated){$rows+=@(Get-WidgetGeneratedQuotes $DataDir)}
  $pools=@{};foreach($group in @('preferred','shown','unseen')){$pools[$group]=New-Object 'System.Collections.Generic.List[object]'};$keys=@{}
  foreach($row in $rows){
    $id=Get-WidgetQuoteKey $row.text
    if($keys.ContainsKey($id)){continue};$keys[$id]=$true
    $group=if($row.preferred){'preferred'}elseif($History.shown.ContainsKey($id)){'shown'}else{'unseen'}
    $pools[$group].Add([pscustomobject]@{text=$row.text;key=$id;group=$group})
  }
  return $pools
}
function Get-WidgetShuffledKeys($Keys) {
  $items=@($Keys)
  for($i=$items.Count-1;$i-gt 0;$i--){$j=$script:widgetQuoteRandom.Next($i+1);$temporary=$items[$i];$items[$i]=$items[$j];$items[$j]=$temporary}
  foreach($item in $items){$item}
}
function Sync-WidgetQuoteRound($Rows,$Previous) {
  $members=@($Rows|ForEach-Object{$_.key});$current=@{};$old=@{};$queued=@{}
  foreach($id in $members){$current[$id]=$true}
  foreach($id in @($Previous.members)){if($id){$old[$id]=$true}}
  $remaining=@(foreach($id in @($Previous.remaining)){if($id -and $current.ContainsKey($id) -and !$queued.ContainsKey($id)){$queued[$id]=$true;$id}})
  $new=@($members|Where-Object{!$old.ContainsKey($_)})
  $remaining+=@(Get-WidgetShuffledKeys $new)
  if(!$remaining.Count -and $members.Count){$remaining=@(Get-WidgetShuffledKeys $members)}
  return @{members=$members;remaining=$remaining}
}
function Get-WidgetSelectedQuote([string]$DataDir) {
  $settings=Get-WidgetSelectionSettings $DataDir;$history=Read-WidgetQuoteHistory $DataDir
  $pools=Get-WidgetSelectionPools $DataDir $settings $history
  $active=@('preferred','shown','unseen'|Where-Object{$settings[$_]-gt 0 -and $pools[$_].Count-gt 0})
  $directory=[IO.Path]::GetFullPath($DataDir)
  if(!$script:widgetQuotePending){$script:widgetQuotePending=@{}}
  $script:widgetQuotePending.Remove($directory)
  if(!$active.Count){
    $script:widgetQuotePending[$directory]=@{empty=$true}
    if(($pools.preferred.Count+$pools.shown.Count+$pools.unseen.Count)-eq 0){return '语录库存为空，请在“编辑我的语录”中添加。'}
    return '当前配比下没有可用语录，请在“编辑我的语录”中调整占比。'
  }
  $total=0;foreach($group in $active){$total+=$settings[$group]}
  $draw=$script:widgetQuoteRandom.NextDouble()*$total;$chosen=$active[$active.Count-1]
  foreach($group in $active){$draw-=$settings[$group];if($draw-lt 0){$chosen=$group;break}}
  $rotation=@{}
  foreach($group in @('preferred','shown','unseen')){$rotation[$group]=Sync-WidgetQuoteRound $pools[$group] $history.rotation[$group]}
  $round=$rotation[$chosen];$id=$round.remaining[0]
  # Keep the chosen class even if its only remaining line was just displayed.
  # At round boundaries we may reorder within a class, never its probability.
  if($id-eq $history.lastKey -and $round.remaining.Count-gt 1){$round.remaining[0]=$round.remaining[1];$round.remaining[1]=$id;$id=$round.remaining[0]}
  $row=@($pools[$chosen]|Where-Object{$_.key-eq $id})[0]
  $round.remaining=@($round.remaining|Select-Object -Skip 1)
  $script:widgetQuotePending[$directory]=@{key=$id;group=$chosen;rotation=$rotation}
  return [string]$row.text
}
function Complete-WidgetQuoteSelection([string]$DataDir,[string]$Key,$History) {
  $directory=[IO.Path]::GetFullPath($DataDir)
  if($script:widgetQuotePending -and $script:widgetQuotePending.ContainsKey($directory)){
    $pending=$script:widgetQuotePending[$directory]
    if($pending.key-eq $Key){$History.rotation=$pending.rotation}
    $script:widgetQuotePending.Remove($directory)
  }
  $History.lastKey=$Key
}
