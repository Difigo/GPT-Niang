function Disable-WidgetQuoteGeneration {
  $settings=Get-WidgetGenerationSettings $script:dataDir
  $settings.enabled=$false
  Save-WidgetGenerationSettings $script:dataDir $settings
  if(!$script:collapsed -and $script:bubbleMode-eq 'quote'){Switch-Scene 'quota'}
}
function Update-WidgetGenerationFeedback {
  if(!$script:generationEditor){return}
  $settings=Get-WidgetGenerationSettings $script:dataDir
  $base=Get-WidgetQuoteSettings $script:dataDir
  $generated=@();try{$generated=@(Read-WidgetQuoteFile (Join-Path $script:dataDir 'generated-quotes.json'))}catch{}
  $rows=@($base.quotes);if($settings.enabled){$rows+=@($generated)}
  $history=Read-WidgetQuoteHistory $script:dataDir;$keys=@{};$unseen=0
  foreach($row in $rows){$key=Get-WidgetQuoteKey $row.text;if(!$keys.ContainsKey($key)){$keys[$key]=$true;if(!$history.shown.ContainsKey($key)){$unseen++}}}
  $status='已关闭，不会启动生成任务。'
  if($settings.enabled){$status='已开启，等待 Codex 与挂件可见、库存不足且符合调用限制。'}
  try{
    $state=[IO.File]::ReadAllText((Join-Path $script:dataDir 'quote-generation-state.json'),[Text.Encoding]::UTF8)|ConvertFrom-Json
    if($settings.enabled){
      switch($state.status){
        'generating' {$status='正在后台生成…关闭开关可取消。'}
        'ready' {$status='上次补充 '+$state.added+' 句，等待下次库存不足。'}
        'cancelled' {$status='上次任务已取消，仍受每日次数和间隔限制。'}
        'failed' {$status=if($state.error-eq 'AUTH_REQUIRED'){'请在本机 Codex 使用 ChatGPT 账号与 OpenAI 提供方。'}else{'上次生成失败；请检查 Codex 版本、网络和模型是否可用。失败计入调用限制。'}}
      }
    }
    $day=[DateTime]::Now.ToString('yyyy-MM-dd')
    if($state.day-eq $day){$status+=' 今日任务 '+$state.attempts+'/'+$settings.maxDaily+' 次。'}
  }catch{}
  $script:generationEditor.FindName('Inventory').Text='当前未展示 '+$unseen+' 句 · 保存的生成台词 '+$generated.Count+' 句。'
  $script:generationEditor.FindName('Status').Text=$status
}
function Open-QuoteGenerationSettings([switch]$CheckOnly) {
  if($script:generationEditor -and $script:generationEditor.IsVisible){$script:generationEditor.Activate()|Out-Null;return}
  $editor=[Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="GPT 娘 · 自动补充台词" Width="580" Height="720" MinWidth="460" MinHeight="440" ShowInTaskbar="False" FontFamily="Microsoft YaHei UI" FontSize="14" Background="#FAF8FD" WindowStartupLocation="CenterOwner">
 <DockPanel Margin="22" Background="#FAF8FD">
  <StackPanel DockPanel.Dock="Bottom" Margin="0,12,0,0">
   <TextBlock x:Name="Feedback" TextWrapping="Wrap" Foreground="#745A98" Margin="0,0,0,10"/>
   <StackPanel Orientation="Horizontal" HorizontalAlignment="Right"><Button x:Name="Save" Content="保存并应用" Padding="18,7" Margin="0,0,10,0"/><Button x:Name="Done" Content="关闭窗口" Padding="18,7"/></StackPanel>
  </StackPanel>
  <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel Margin="0,0,10,0">
   <TextBlock Text="用本机 Codex 为 GPT 娘补充新台词" FontSize="19" FontWeight="Bold" Foreground="#443552" Margin="0,0,0,12"/>
   <TextBlock Text="默认关闭。开启后会调用模型并消耗 Codex 额度。只有 Codex 窗口与挂件可见时才启动补货；生成不使用你的聊天历史。" TextWrapping="Wrap" Foreground="#745A98" Margin="0,0,0,12"/>
   <CheckBox x:Name="Enabled" Content="启用自动补充（勾选后保存生效；取消勾选立即停止）" Margin="0,0,0,14"/>
   <TextBlock x:Name="Inventory" TextWrapping="Wrap" Foreground="#443552" Margin="0,0,0,6"/>
   <TextBlock x:Name="Status" TextWrapping="Wrap" Foreground="#745A98" Margin="0,0,0,14"/>
   <TextBlock Text="补货阈值：未展示库存少于多少句（1–1000）"/><TextBox x:Name="Threshold" Margin="0,5,0,10" Padding="8,5"/>
   <TextBlock Text="每批请求句数（1–200；GPT = G7 + P16 + T20 = 43）"/><TextBox x:Name="BatchSize" Margin="0,5,0,10" Padding="8,5"/>
   <TextBlock Text="每日最多任务次数（1–100，失败和取消也计数）"/><TextBox x:Name="MaxDaily" Margin="0,5,0,10" Padding="8,5"/>
   <TextBlock Text="最小调用间隔：分钟（1–1440）"/><TextBox x:Name="MinIntervalMinutes" Margin="0,5,0,10" Padding="8,5"/>
   <TextBlock Text="模型名（留空沿用 Codex CLI 的模型配置）"/><TextBox x:Name="Model" Margin="0,5,0,5" Padding="8,5"/>
   <TextBlock Text="需当前 ChatGPT 账号支持。这里的设置只影响台词生成，不修改 Codex 的全局配置或当前聊天模型。" TextWrapping="Wrap" Foreground="#745A98" Margin="0,0,0,14"/>
   <TextBlock Text="人设与台词规则（每批独立提供，可修改）"/><TextBox x:Name="Persona" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Height="190" Margin="0,5,0,8" Padding="8"/>
   <Button x:Name="PersonaDefault" Content="恢复默认人设与规则" HorizontalAlignment="Left" Padding="12,6"/>
   <TextBlock Text="关闭后只展示原有语录，保留生成库存与历史。展示历史从新版首次运行就记录，与生成开关无关。取消不能撤回已经发生的额度消耗。" TextWrapping="Wrap" Foreground="#745A98" Margin="0,14,0,0"/>
  </StackPanel></ScrollViewer>
 </DockPanel>
</Window>
'@)
  $script:generationEditor=$editor;$editor.Owner=$script:window
  $settings=Get-WidgetGenerationSettings $script:dataDir
  $editor.FindName('Enabled').IsChecked=$settings.enabled
  foreach($name in @('Threshold','BatchSize','MaxDaily','MinIntervalMinutes','Model','Persona')){$editor.FindName($name).Text=[string]$settings[$name]}
  $editor.FindName('Enabled').Add_Unchecked({
    try{Disable-WidgetQuoteGeneration;Update-WidgetGenerationFeedback;$script:generationEditor.FindName('Feedback').Text='已停止自动生成，重启也保持关闭。'}
    catch{$script:generationEditor.FindName('Enabled').IsChecked=$true;$script:generationEditor.FindName('Feedback').Text='关闭设置未能保存，请重试。'}
  })
  $editor.FindName('Save').Add_Click({
    try{
      $value=@{enabled=[bool]$script:generationEditor.FindName('Enabled').IsChecked}
      foreach($name in @('Threshold','BatchSize','MaxDaily','MinIntervalMinutes','Model','Persona')){$value[$name]=$script:generationEditor.FindName($name).Text.Trim()}
      Save-WidgetGenerationSettings $script:dataDir $value
      if(!$value.enabled -and !$script:collapsed -and $script:bubbleMode-eq 'quote'){Switch-Scene 'quota'}
      Update-WidgetGenerationFeedback;$script:generationEditor.FindName('Feedback').Text='已保存。库存、模型和调用限制将在后台检查时应用。'
    }catch{$script:generationEditor.FindName('Feedback').Text=$_.Exception.Message}
  })
  $editor.FindName('PersonaDefault').Add_Click({
    $file=Join-Path $script:appDir 'assets\quote-persona.txt'
    $script:generationEditor.FindName('Persona').Text=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8).Trim()
  })
  $editor.FindName('Done').Add_Click({$script:generationEditor.Close()})
  $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromSeconds(1)
  $timer.Add_Tick({Update-WidgetGenerationFeedback});$editor.Tag=$timer
  $editor.Add_Closed({param($sender,$event)$sender.Tag.Stop();$script:generationEditor=$null})
  Update-WidgetGenerationFeedback
  if($CheckOnly){return $editor}
  $editor.Show();$timer.Start()
}
