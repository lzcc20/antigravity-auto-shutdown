param(
    [string]$DataDir = "",
    [string]$I18nPath = "",
    [switch]$StartExpanded,
    [switch]$ForceShow,
    [switch]$AllowSecondInstance,
    [string]$OverrideTheme = "",
    [string]$CapturePath = "",
    [int]$CaptureDelayMs = 900
)

$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Resolve paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $DataDir = Join-Path $env:USERPROFILE ".gemini\config\auto-shutdown"
}
if ([string]::IsNullOrWhiteSpace($I18nPath)) {
    $I18nPath = Join-Path $ScriptDir "i18n.json"
}
if (!(Test-Path $DataDir)) {
    New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
}

$CtlScript = Join-Path $ScriptDir "ctl.mjs"
$ConfigPath = Join-Path $DataDir "config.json"
$StatePath = Join-Path $DataDir "state.json"
$WakeupSignalPath = Join-Path $DataDir "widget-wakeup.signal"

# Single-instance guard (unless AllowSecondInstance for isolated preview/capture)
$script:Mutex = $null
if (-not $AllowSecondInstance) {
    $createdNew = $false
    $script:Mutex = New-Object System.Threading.Mutex($true, "Local\AntigravityAutoShutdownWidget_v1", [ref]$createdNew)
    if (-not $createdNew) {
        if ($ForceShow -or $StartExpanded) {
            $payload = if ($StartExpanded) { "expand:$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())" } else { "show:$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())" }
            [System.IO.File]::WriteAllText($WakeupSignalPath, $payload, [System.Text.Encoding]::UTF8)
        }
        exit 0
    }
}

# Load UTF-8 i18n dictionary cleanly
$script:I18n = $null
try {
    $rawI18n = [System.IO.File]::ReadAllText($I18nPath, [System.Text.Encoding]::UTF8)
    $script:I18n = $rawI18n | ConvertFrom-Json
} catch {
    $script:I18n = $null
}

function Get-Text {
    param([string]$Key, [hashtable]$Vars = @{})
    $lang = if ($script:Config -and $script:Config.language) { $script:Config.language } else { "zh-CN" }
    $val = $Key
    if ($script:I18n) {
        $dict = $script:I18n.$lang
        if (-not $dict) { $dict = $script:I18n."zh-CN" }
        if ($dict -and $dict.PSObject.Properties[$Key]) {
            $val = [string]$dict.$Key
        }
    }
    foreach ($k in $Vars.Keys) {
        $val = $val.Replace("{$k}", [string]$Vars[$k])
    }
    return $val
}

function Get-SystemIsDark {
    try {
        $val = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -ErrorAction Stop
        return ($val -eq 0)
    } catch {
        return $true
    }
}

function New-Brush {
    param([string]$Hex)
    $c = [System.Windows.Media.ColorConverter]::ConvertFromString($Hex)
    $b = New-Object System.Windows.Media.SolidColorBrush($c)
    $b.Freeze()
    return $b
}

function Read-JsonFile {
    param([string]$Path)
    if (!(Test-Path $Path)) { return $null }
    for ($i = 0; $i -lt 4; $i++) {
        try {
            $txt = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
            if ([string]::IsNullOrWhiteSpace($txt)) { return $null }
            return ($txt | ConvertFrom-Json)
        } catch {
            Start-Sleep -Milliseconds 15
        }
    }
    return $null
}

function Invoke-CtlAsync {
    param([string[]]$Arguments)
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "node"
        $argList = @("`"$CtlScript`"")
        foreach ($a in $Arguments) {
            if ($a -match '\s') { $argList += "`"$a`"" } else { $argList += $a }
        }
        $argList += "--data-dir"
        $argList += "`"$DataDir`""
        $psi.Arguments = ($argList -join " ")
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        [System.Diagnostics.Process]::Start($psi) | Out-Null
    } catch {}
}

function Format-Duration {
    param([int]$TotalSeconds)
    if ($TotalSeconds -lt 0) { $TotalSeconds = 0 }
    $mins = [int][Math]::Floor($TotalSeconds / 60)
    $secs = [int]($TotalSeconds % 60)
    return ("{0:D2}:{1:D2}" -f $mins, $secs)
}

function Get-ActionLabel {
    param([string]$Action)
    switch ($Action) {
        "hibernate" { return (Get-Text "actionHibernate") }
        "sleep"     { return (Get-Text "actionSleep") }
        default     { return (Get-Text "actionShutdown") }
    }
}

# Color palettes: Obsidian Matte Dark & Warm Alabaster Paper Light
$Palettes = @{
    dark = @{
        Surface          = "#F416181C"
        SurfaceSubtle    = "#FF1D2026"
        SurfaceInset     = "#FF121418"
        SurfaceHover     = "#FF262A32"
        SegmentActive    = "#FF2D313B"
        SegmentBorder    = "#FF3E4452"
        Border           = "#FF292C34"
        Divider          = "#FF23262E"
        InkPrimary       = "#FFF2F3F5"
        InkSecondary     = "#FF9399A6"
        InkMuted         = "#FF616775"
        DotStandby       = "#FF6C7280"
        DotArmed         = "#FF7CC9A0"
        DotRunning       = "#FFE3A857"
        DotCountdown     = "#FFE06C65"
        ArmedBg          = "#247CC9A0"
        ArmedBorder      = "#4D7CC9A0"
        ArmedInk         = "#FF91D8B2"
        CountdownBg      = "#1FE06C65"
        CountdownBorder  = "#4AE06C65"
        CountdownInk     = "#FFF08A84"
        CancelBtnBg      = "#2EE06C65"
        CancelBtnHover   = "#45E06C65"
        PreviewBg        = "#24E3A857"
        PreviewBorder    = "#4CE3A857"
        PreviewInk       = "#FFF0BE78"
        SwitchOffBg      = "#FF2A2E37"
        SwitchOnBg       = "#FF5EA881"
        SwitchThumb      = "#FFF4F5F7"
        ProgressTrack    = "#FF252830"
        ShadowOpacity    = 0.42
    }
    light = @{
        Surface          = "#F7FAF9F6"
        SurfaceSubtle    = "#FFF1EFEA"
        SurfaceInset     = "#FFF4F2ED"
        SurfaceHover     = "#FFE8E5DE"
        SegmentActive    = "#FFFFFFFF"
        SegmentBorder    = "#FFDAD6CD"
        Border           = "#FFE0DDD5"
        Divider          = "#FFE9E6DF"
        InkPrimary       = "#FF1A1B1E"
        InkSecondary     = "#FF636770"
        InkMuted         = "#FF9296A0"
        DotStandby       = "#FF9599A3"
        DotArmed         = "#FF2F855A"
        DotRunning       = "#FFC2781A"
        DotCountdown     = "#FFC84B45"
        ArmedBg          = "#1C2F855A"
        ArmedBorder      = "#442F855A"
        ArmedInk         = "#FF226B46"
        CountdownBg      = "#16C84B45"
        CountdownBorder  = "#3EC84B45"
        CountdownInk     = "#FFB33A35"
        CancelBtnBg      = "#22C84B45"
        CancelBtnHover   = "#36C84B45"
        PreviewBg        = "#1DC2781A"
        PreviewBorder    = "#44C2781A"
        PreviewInk       = "#FF9A5C0E"
        SwitchOffBg      = "#FFD8D5CD"
        SwitchOnBg       = "#FF2F855A"
        SwitchThumb      = "#FFFFFFFF"
        ProgressTrack    = "#FFE4E1D9"
        ShadowOpacity    = 0.18
    }
}

# Build WPF XAML with pure custom styles (zero default Win32 gray chrome)
[xml]$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Auto Shutdown"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        ResizeMode="NoResize"
        ShowInTaskbar="False"
        Topmost="True"
        SizeToContent="WidthAndHeight"
        UseLayoutRounding="True"
        SnapsToDevicePixels="True"
        TextOptions.TextFormattingMode="Ideal"
        TextOptions.TextRenderingMode="ClearType"
        FontFamily="Segoe UI Variable Text, Segoe UI, Microsoft YaHei UI">

    <Window.Resources>
        <Style x:Key="GhostIconButton" TargetType="Button">
            <Setter Property="Width" Value="26"/>
            <Setter Property="Height" Value="26"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="8">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BrushHover}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="PillButton" TargetType="Button">
            <Setter Property="Height" Value="26"/>
            <Setter Property="Padding" Value="11,0"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="FontWeight" Value="Medium"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="13"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.88"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.74"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="SegmentButton" TargetType="Button">
            <Setter Property="Height" Value="26"/>
            <Setter Property="FontSize" Value="11.5"/>
            <Setter Property="FontWeight" Value="Normal"/>
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderBrush" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="7"
                                Padding="6,0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.88"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="CardActionButton" TargetType="Button">
            <Setter Property="Height" Value="32"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="Medium"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="9"
                                Padding="10,0">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.88"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.74"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="GhostLinkButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="6,2"/>
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FocusVisualStyle" Value="{x:Null}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Background" Value="{DynamicResource BrushHover}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <!-- Shadow safe outer padding -->
    <Grid Margin="18">

        <!-- ==================== COMPACT BOTTOM-RIGHT PILL ==================== -->
        <Border x:Name="PillView"
                Height="40"
                MinWidth="226"
                CornerRadius="20"
                BorderThickness="1"
                Visibility="Visible"
                ClipToBounds="False">
            <Border.Effect>
                <DropShadowEffect x:Name="PillShadow" BlurRadius="22" ShadowDepth="5" Direction="270" Color="#000000" Opacity="0.38"/>
            </Border.Effect>
            <Grid>
                <Grid x:Name="PillDragArea" Margin="14,0,7,0">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <!-- Breathing Status Dot -->
                    <Grid Grid.Column="0" Width="14" Height="14" VerticalAlignment="Center" Margin="0,0,8,0">
                        <Ellipse x:Name="PillDotHalo" Width="14" Height="14" Opacity="0.22"/>
                        <Ellipse x:Name="PillDot" Width="7" Height="7"/>
                    </Grid>

                    <!-- Status Text -->
                    <TextBlock x:Name="PillStatusText"
                               Grid.Column="1"
                               VerticalAlignment="Center"
                               FontSize="12.5"
                               FontWeight="Medium"
                               Margin="0,0,12,0"
                               Text="Idle"/>

                    <!-- Quick Arm / Cancel Button -->
                    <Button x:Name="PillQuickBtn"
                            Grid.Column="2"
                            Style="{StaticResource PillButton}"
                            Margin="0,0,4,0"
                            Content="Arm"/>

                    <!-- Expand Chevron -->
                    <Button x:Name="PillExpandBtn"
                            Grid.Column="3"
                            Style="{StaticResource GhostIconButton}"
                            Width="26" Height="26">
                        <Path x:Name="PillExpandIcon" Data="M 1 5 L 5 1 L 9 5" StrokeThickness="1.6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Width="10" Height="6" Stretch="None"/>
                    </Button>
                </Grid>

                <!-- Ultra-thin bottom countdown hairline -->
                <Border x:Name="PillProgressContainer"
                        VerticalAlignment="Bottom"
                        Height="2"
                        Margin="20,0,20,0"
                        CornerRadius="1"
                        Visibility="Collapsed"
                        ClipToBounds="True">
                    <Border x:Name="PillProgressFill" HorizontalAlignment="Left" Height="2" Width="0" CornerRadius="1"/>
                </Border>
            </Grid>
        </Border>

        <!-- ==================== EXPANDED MINIMALIST CARD ==================== -->
        <Border x:Name="CardView"
                Width="332"
                CornerRadius="16"
                BorderThickness="1"
                Visibility="Collapsed">
            <Border.Effect>
                <DropShadowEffect x:Name="CardShadow" BlurRadius="28" ShadowDepth="8" Direction="270" Color="#000000" Opacity="0.42"/>
            </Border.Effect>

            <StackPanel>
                <!-- Header -->
                <Grid x:Name="CardDragHeader" Margin="16,13,10,11">
                    <Grid.ColumnDefinitions>
                        <ColumnDefinition Width="Auto"/>
                        <ColumnDefinition Width="*"/>
                        <ColumnDefinition Width="Auto"/>
                    </Grid.ColumnDefinitions>

                    <!-- Minimalist Geometric Power-Orbit Icon -->
                    <Canvas Grid.Column="0" Width="18" Height="18" VerticalAlignment="Center" Margin="0,0,9,0">
                        <Path x:Name="LogoArc" Data="M 5.2,4.4 A 6.2,6.2 0 1 0 12.8,4.4" StrokeThickness="1.7" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                        <Line x:Name="LogoStem" X1="9" Y1="2.2" X2="9" Y2="8.4" StrokeThickness="1.7" StrokeStartLineCap="Round" StrokeEndLineCap="Round"/>
                        <Ellipse x:Name="LogoDot" Width="3" Height="3" Canvas.Left="7.5" Canvas.Top="11.2"/>
                    </Canvas>

                    <!-- Title + Status Chip -->
                    <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                        <TextBlock x:Name="CardTitle" FontSize="13" FontWeight="SemiBold" VerticalAlignment="Center" Text="Auto Shutdown"/>
                        <Border x:Name="StatusBadge" CornerRadius="9" Padding="7,2" Margin="8,0,0,0" VerticalAlignment="Center" BorderThickness="1">
                            <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                                <Ellipse x:Name="BadgeDot" Width="5" Height="5" Margin="0,0,5,0" VerticalAlignment="Center"/>
                                <TextBlock x:Name="BadgeText" FontSize="10.5" FontWeight="Medium" VerticalAlignment="Center" Text="STANDBY"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>

                    <!-- Header Utility Icons -->
                    <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
                        <Button x:Name="BtnLang" Style="{StaticResource GhostIconButton}">
                            <TextBlock x:Name="BtnLangText" FontSize="10.5" FontWeight="SemiBold" Text="EN"/>
                        </Button>
                        <Button x:Name="BtnTheme" Style="{StaticResource GhostIconButton}">
                            <Grid Width="14" Height="14">
                                <Path x:Name="IconMoon" Data="M 7,1.5 A 5.5,5.5 0 1 0 12.5,7 A 4.2,4.2 0 0 1 7,1.5 Z" StrokeThickness="1.35" StrokeLineJoin="Round" Visibility="Collapsed"/>
                                <Path x:Name="IconSun" Data="M 7,4.2 A 2.8,2.8 0 1 0 7,9.8 A 2.8,2.8 0 1 0 7,4.2 M 7,1.2 L 7,2.4 M 7,11.6 L 7,12.8 M 1.2,7 L 2.4,7 M 11.6,7 L 12.8,7 M 2.9,2.9 L 3.8,3.8 M 10.2,10.2 L 11.1,11.1 M 11.1,2.9 L 10.2,3.8 M 3.8,10.2 L 2.9,11.1" StrokeThickness="1.35" StrokeStartLineCap="Round" StrokeEndLineCap="Round" Visibility="Visible"/>
                            </Grid>
                        </Button>
                        <Button x:Name="BtnCollapse" Style="{StaticResource GhostIconButton}">
                            <Path x:Name="IconCollapse" Data="M 1 1 L 5 5 L 9 1" StrokeThickness="1.6" StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Width="10" Height="6" Stretch="None"/>
                        </Button>
                        <Button x:Name="BtnHide" Style="{StaticResource GhostIconButton}">
                            <Path x:Name="IconHide" Data="M 1 1 L 7 7 M 7 1 L 1 7" StrokeThickness="1.5" StrokeStartLineCap="Round" Width="8" Height="8" Stretch="None"/>
                        </Button>
                    </StackPanel>
                </Grid>

                <Rectangle x:Name="Div1" Height="1"/>

                <!-- Countdown Hero Panel (shown only when countdown active) -->
                <Border x:Name="CountdownPanel"
                        Margin="14,12,14,0"
                        CornerRadius="12"
                        BorderThickness="1"
                        Padding="14,14,14,12"
                        Visibility="Collapsed">
                    <StackPanel>
                        <TextBlock x:Name="CountdownTimerText"
                                   HorizontalAlignment="Center"
                                   FontFamily="Segoe UI Variable Display, Segoe UI"
                                   FontSize="36"
                                   FontWeight="Light"
                                   Text="02:00"/>
                        <TextBlock x:Name="CountdownSubtitle"
                                   HorizontalAlignment="Center"
                                   FontSize="11.5"
                                   Margin="0,3,0,11"
                                   Text="All tasks finished"/>

                        <!-- Countdown Progress Track -->
                        <Border x:Name="CardProgressTrack" Height="3" CornerRadius="1.5" ClipToBounds="True" Margin="0,0,0,12">
                            <Border x:Name="CardProgressFill" HorizontalAlignment="Left" Height="3" Width="260" CornerRadius="1.5"/>
                        </Border>

                        <!-- Action Buttons -->
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="1.65*"/>
                                <ColumnDefinition Width="8"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="BtnCancelCountdown" Grid.Column="0" Style="{StaticResource CardActionButton}" Content="Cancel"/>
                            <Button x:Name="BtnExecuteNow" Grid.Column="2" Style="{StaticResource CardActionButton}" Content="Now"/>
                        </Grid>
                    </StackPanel>
                </Border>

                <!-- Active Tasks Section -->
                <StackPanel Margin="16,12,16,12">
                    <Grid Margin="0,0,0,8">
                        <TextBlock x:Name="LblTasksTitle" FontSize="11" FontWeight="Medium" VerticalAlignment="Center" Text="ACTIVE TASKS"/>
                        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                            <TextBlock x:Name="LblTasksCount" FontSize="11" VerticalAlignment="Center" Text="0"/>
                            <Button x:Name="BtnClearStale" Style="{StaticResource GhostLinkButton}" Margin="6,0,0,0" Visibility="Collapsed" Content="Clear"/>
                        </StackPanel>
                    </Grid>

                    <Border x:Name="TasksBox" CornerRadius="10" BorderThickness="1" Padding="11,9">
                        <Grid>
                            <StackPanel x:Name="TasksEmptyPanel" Orientation="Horizontal" VerticalAlignment="Center">
                                <Ellipse x:Name="TasksEmptyDot" Width="5" Height="5" Margin="0,0,8,0" VerticalAlignment="Center"/>
                                <TextBlock x:Name="LblTasksEmpty" FontSize="12" VerticalAlignment="Center" Text="No active Antigravity tasks"/>
                            </StackPanel>
                            <ScrollViewer x:Name="TasksScroll" MaxHeight="114" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                                <StackPanel x:Name="TasksListPanel"/>
                            </ScrollViewer>
                        </Grid>
                    </Border>
                </StackPanel>

                <Rectangle x:Name="Div2" Height="1"/>

                <!-- Controls Section -->
                <StackPanel Margin="16,12,16,12">

                    <!-- Guard Mode Segmented Control -->
                    <TextBlock x:Name="LblMode" FontSize="11" FontWeight="Medium" Margin="0,0,0,6" Text="GUARD MODE"/>
                    <Border x:Name="TrackMode" CornerRadius="10" Padding="3" Margin="0,0,0,12">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="SegModeOff"  Grid.Column="0" Style="{StaticResource SegmentButton}" Content="Off"/>
                            <Button x:Name="SegModeOnce" Grid.Column="1" Style="{StaticResource SegmentButton}" Content="One-shot"/>
                            <Button x:Name="SegModeCont" Grid.Column="2" Style="{StaticResource SegmentButton}" Content="Always"/>
                        </Grid>
                    </Border>

                    <!-- Power Action Segmented Control -->
                    <TextBlock x:Name="LblAction" FontSize="11" FontWeight="Medium" Margin="0,0,0,6" Text="POWER ACTION"/>
                    <Border x:Name="TrackAction" CornerRadius="10" Padding="3" Margin="0,0,0,12">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="SegActShutdown"  Grid.Column="0" Style="{StaticResource SegmentButton}" Content="Shutdown"/>
                            <Button x:Name="SegActHibernate" Grid.Column="1" Style="{StaticResource SegmentButton}" Content="Hibernate"/>
                            <Button x:Name="SegActSleep"     Grid.Column="2" Style="{StaticResource SegmentButton}" Content="Sleep"/>
                        </Grid>
                    </Border>

                    <!-- Grace Period Segmented Control -->
                    <TextBlock x:Name="LblGrace" FontSize="11" FontWeight="Medium" Margin="0,0,0,6" Text="GRACE PERIOD"/>
                    <Border x:Name="TrackGrace" CornerRadius="10" Padding="3" Margin="0,0,0,13">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Button x:Name="SegGrace30"  Grid.Column="0" Style="{StaticResource SegmentButton}" Content="30s"/>
                            <Button x:Name="SegGrace60"  Grid.Column="1" Style="{StaticResource SegmentButton}" Content="60s"/>
                            <Button x:Name="SegGrace120" Grid.Column="2" Style="{StaticResource SegmentButton}" Content="2m"/>
                            <Button x:Name="SegGrace300" Grid.Column="3" Style="{StaticResource SegmentButton}" Content="5m"/>
                        </Grid>
                    </Border>

                    <!-- Toggle Rows -->
                    <Grid Margin="0,0,0,8">
                        <TextBlock x:Name="LblOptIgnoreCancel" FontSize="12" VerticalAlignment="Center" Text="Skip on manual cancel"/>
                        <Border x:Name="SwitchIgnoreCancel" HorizontalAlignment="Right" Width="34" Height="19" CornerRadius="9.5" Cursor="Hand">
                            <Ellipse x:Name="ThumbIgnoreCancel" Width="13" Height="13" VerticalAlignment="Center" HorizontalAlignment="Left" Margin="3,0,0,0"/>
                        </Border>
                    </Grid>

                    <Grid>
                        <TextBlock x:Name="LblOptTopmost" FontSize="12" VerticalAlignment="Center" Text="Always on top"/>
                        <Border x:Name="SwitchTopmost" HorizontalAlignment="Right" Width="34" Height="19" CornerRadius="9.5" Cursor="Hand">
                            <Ellipse x:Name="ThumbTopmost" Width="13" Height="13" VerticalAlignment="Center" HorizontalAlignment="Left" Margin="3,0,0,0"/>
                        </Border>
                    </Grid>
                </StackPanel>

                <Rectangle x:Name="Div3" Height="1"/>

                <!-- Footer -->
                <Grid Margin="16,8,10,9">
                    <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                        <Ellipse x:Name="FooterDot" Width="5" Height="5" Margin="0,0,6,0" VerticalAlignment="Center"/>
                        <TextBlock x:Name="LblFooter" FontSize="10.5" VerticalAlignment="Center" Text="Hooks ready"/>
                    </StackPanel>
                    <Button x:Name="BtnPreview" HorizontalAlignment="Right" Style="{StaticResource GhostLinkButton}" Content="Preview"/>
                </Grid>
            </StackPanel>
        </Border>
    </Grid>
</Window>
"@

$Reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($Reader)

# Helper to bind controls
function Find-Ctrl([string]$Name) { return $Window.FindName($Name) }

$PillView              = Find-Ctrl "PillView"
$PillShadow            = Find-Ctrl "PillShadow"
$PillDragArea          = Find-Ctrl "PillDragArea"
$PillDotHalo           = Find-Ctrl "PillDotHalo"
$PillDot               = Find-Ctrl "PillDot"
$PillStatusText        = Find-Ctrl "PillStatusText"
$PillQuickBtn          = Find-Ctrl "PillQuickBtn"
$PillExpandBtn         = Find-Ctrl "PillExpandBtn"
$PillExpandIcon        = Find-Ctrl "PillExpandIcon"
$PillProgressContainer = Find-Ctrl "PillProgressContainer"
$PillProgressFill      = Find-Ctrl "PillProgressFill"

$CardView              = Find-Ctrl "CardView"
$CardShadow            = Find-Ctrl "CardShadow"
$CardDragHeader        = Find-Ctrl "CardDragHeader"
$LogoArc               = Find-Ctrl "LogoArc"
$LogoStem              = Find-Ctrl "LogoStem"
$LogoDot               = Find-Ctrl "LogoDot"
$CardTitle             = Find-Ctrl "CardTitle"
$StatusBadge           = Find-Ctrl "StatusBadge"
$BadgeDot              = Find-Ctrl "BadgeDot"
$BadgeText             = Find-Ctrl "BadgeText"
$BtnLang               = Find-Ctrl "BtnLang"
$BtnLangText           = Find-Ctrl "BtnLangText"
$BtnTheme              = Find-Ctrl "BtnTheme"
$IconMoon              = Find-Ctrl "IconMoon"
$IconSun               = Find-Ctrl "IconSun"
$BtnCollapse           = Find-Ctrl "BtnCollapse"
$IconCollapse          = Find-Ctrl "IconCollapse"
$BtnHide               = Find-Ctrl "BtnHide"
$IconHide              = Find-Ctrl "IconHide"
$Div1                  = Find-Ctrl "Div1"
$Div2                  = Find-Ctrl "Div2"
$Div3                  = Find-Ctrl "Div3"

$CountdownPanel        = Find-Ctrl "CountdownPanel"
$CountdownTimerText    = Find-Ctrl "CountdownTimerText"
$CountdownSubtitle     = Find-Ctrl "CountdownSubtitle"
$CardProgressTrack     = Find-Ctrl "CardProgressTrack"
$CardProgressFill      = Find-Ctrl "CardProgressFill"
$BtnCancelCountdown    = Find-Ctrl "BtnCancelCountdown"
$BtnExecuteNow         = Find-Ctrl "BtnExecuteNow"

$LblTasksTitle         = Find-Ctrl "LblTasksTitle"
$LblTasksCount         = Find-Ctrl "LblTasksCount"
$BtnClearStale         = Find-Ctrl "BtnClearStale"
$TasksBox              = Find-Ctrl "TasksBox"
$TasksEmptyPanel       = Find-Ctrl "TasksEmptyPanel"
$TasksEmptyDot         = Find-Ctrl "TasksEmptyDot"
$LblTasksEmpty         = Find-Ctrl "LblTasksEmpty"
$TasksScroll           = Find-Ctrl "TasksScroll"
$TasksListPanel        = Find-Ctrl "TasksListPanel"

$LblMode               = Find-Ctrl "LblMode"
$TrackMode             = Find-Ctrl "TrackMode"
$SegModeOff            = Find-Ctrl "SegModeOff"
$SegModeOnce           = Find-Ctrl "SegModeOnce"
$SegModeCont           = Find-Ctrl "SegModeCont"

$LblAction             = Find-Ctrl "LblAction"
$TrackAction           = Find-Ctrl "TrackAction"
$SegActShutdown        = Find-Ctrl "SegActShutdown"
$SegActHibernate       = Find-Ctrl "SegActHibernate"
$SegActSleep           = Find-Ctrl "SegActSleep"

$LblGrace              = Find-Ctrl "LblGrace"
$TrackGrace            = Find-Ctrl "TrackGrace"
$SegGrace30            = Find-Ctrl "SegGrace30"
$SegGrace60            = Find-Ctrl "SegGrace60"
$SegGrace120           = Find-Ctrl "SegGrace120"
$SegGrace300           = Find-Ctrl "SegGrace300"

$LblOptIgnoreCancel    = Find-Ctrl "LblOptIgnoreCancel"
$SwitchIgnoreCancel    = Find-Ctrl "SwitchIgnoreCancel"
$ThumbIgnoreCancel     = Find-Ctrl "ThumbIgnoreCancel"
$LblOptTopmost         = Find-Ctrl "LblOptTopmost"
$SwitchTopmost         = Find-Ctrl "SwitchTopmost"
$ThumbTopmost          = Find-Ctrl "ThumbTopmost"

$FooterDot             = Find-Ctrl "FooterDot"
$LblFooter             = Find-Ctrl "LblFooter"
$BtnPreview            = Find-Ctrl "BtnPreview"

# Runtime state
$script:Expanded = [bool]$StartExpanded
$script:UserDragged = $false
$script:AnchorRight = $null
$script:AnchorBottom = $null
$script:LastWakeupStamp = ""
$script:PulsePhase = 0
$script:CurrentTheme = "dark"
$script:TrayIconState = ""
$script:Config = [PSCustomObject]@{
    armed               = $false
    mode                = "once"
    action              = "shutdown"
    graceSeconds        = 120
    ignoreUserCancel    = $true
    ignoreErrors        = $false
    staleTimeoutMinutes = 15
    alwaysOnTop         = $true
    autoLaunchWidget    = $true
    theme               = "auto"
    language            = "zh-CN"
    dryRun              = $false
}
$script:State = [PSCustomObject]@{
    activeSessions = [PSCustomObject]@{}
    countdown      = [PSCustomObject]@{
        active       = $false
        preview      = $false
        action       = "shutdown"
        startedAt    = $null
        executeAt    = $null
        graceSeconds = 120
    }
    lastEvent      = $null
}

function Snap-BottomRight {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $Window.UpdateLayout()
    # Outer grid has 18px shadow margin; keep visible edge 14px from screen edge/taskbar
    $marginOffset = 4
    if (-not $script:UserDragged -or $null -eq $script:AnchorRight) {
        $script:AnchorRight = $wa.Right - $marginOffset
        $script:AnchorBottom = $wa.Bottom - $marginOffset
    }
    $newLeft = $script:AnchorRight - $Window.ActualWidth
    $newTop = $script:AnchorBottom - $Window.ActualHeight

    # Clamp inside WorkArea
    if ($newLeft -lt ($wa.Left - 14)) { $newLeft = $wa.Left - 14 }
    if ($newTop -lt ($wa.Top - 14)) { $newTop = $wa.Top - 14 }
    if (($newLeft + $Window.ActualWidth) -gt ($wa.Right + 14)) { $newLeft = $wa.Right - $Window.ActualWidth + 14 }
    if (($newTop + $Window.ActualHeight) -gt ($wa.Bottom + 14)) { $newTop = $wa.Bottom - $Window.ActualHeight + 14 }

    $Window.Left = $newLeft
    $Window.Top = $newTop
}

function Set-Expanded {
    param([bool]$Expand)
    $script:Expanded = $Expand
    if ($Expand) {
        $PillView.Visibility = [System.Windows.Visibility]::Collapsed
        $CardView.Visibility = [System.Windows.Visibility]::Visible
    } else {
        $CardView.Visibility = [System.Windows.Visibility]::Collapsed
        $PillView.Visibility = [System.Windows.Visibility]::Visible
    }
    $Window.UpdateLayout()
    Snap-BottomRight
}

function Style-SegmentGroup {
    param($Buttons, $ActiveButton, $P)
    foreach ($btn in $Buttons) {
        if ($btn -eq $ActiveButton) {
            $btn.Background = New-Brush $P.SegmentActive
            $btn.BorderBrush = New-Brush $P.SegmentBorder
            $btn.Foreground = New-Brush $P.InkPrimary
            $btn.FontWeight = [System.Windows.FontWeights]::Medium
        } else {
            $btn.Background = [System.Windows.Media.Brushes]::Transparent
            $btn.BorderBrush = [System.Windows.Media.Brushes]::Transparent
            $btn.Foreground = New-Brush $P.InkSecondary
            $btn.FontWeight = [System.Windows.FontWeights]::Normal
        }
    }
}

function Style-Switch {
    param($Track, $Thumb, [bool]$IsOn, $P)
    $Track.Background = New-Brush $(if ($IsOn) { $P.SwitchOnBg } else { $P.SwitchOffBg })
    $Thumb.Fill = New-Brush $P.SwitchThumb
    $Thumb.Margin = if ($IsOn) { New-Object System.Windows.Thickness(18,0,0,0) } else { New-Object System.Windows.Thickness(3,0,0,0) }
}

function Create-TrayIcon {
    param([string]$DotHex, [bool]$IsDark)
    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)

    $bgColor = if ($IsDark) { [System.Drawing.Color]::FromArgb(245, 24, 26, 31) } else { [System.Drawing.Color]::FromArgb(245, 250, 249, 246) }
    $fgColor = if ($IsDark) { [System.Drawing.Color]::FromArgb(255, 238, 240, 244) } else { [System.Drawing.Color]::FromArgb(255, 28, 30, 34) }
    $borderColor = if ($IsDark) { [System.Drawing.Color]::FromArgb(255, 62, 68, 82) } else { [System.Drawing.Color]::FromArgb(255, 200, 196, 188) }

    $bgBrush = New-Object System.Drawing.SolidBrush($bgColor)
    $g.FillEllipse($bgBrush, 1, 1, 29, 29)
    $borderPen = New-Object System.Drawing.Pen($borderColor, 1.5)
    $g.DrawEllipse($borderPen, 1.5, 1.5, 28, 28)

    $arcPen = New-Object System.Drawing.Pen($fgColor, 2.6)
    $arcPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $arcPen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawArc($arcPen, 8, 8, 16, 16, -50, 280)
    $g.DrawLine($arcPen, 16, 6, 16, 14)

    $dotColor = [System.Drawing.ColorTranslator]::FromHtml($DotHex.Replace("#FF", "#"))
    $dotBrush = New-Object System.Drawing.SolidBrush($dotColor)
    $g.FillEllipse($dotBrush, 13.5, 17.5, 5, 5)

    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    $g.Dispose()
    $bmp.Dispose()
    $bgBrush.Dispose()
    $borderPen.Dispose()
    $arcPen.Dispose()
    $dotBrush.Dispose()
    return $icon
}

function Apply-Theme {
    $themePref = if (-not [string]::IsNullOrWhiteSpace($OverrideTheme)) { $OverrideTheme } elseif ($script:Config.theme) { $script:Config.theme } else { "auto" }
    $resolved = if ($themePref -eq "dark") { "dark" } elseif ($themePref -eq "light") { "light" } else { if (Get-SystemIsDark) { "dark" } else { "light" } }
    $script:CurrentTheme = $resolved
    $P = $Palettes[$resolved]

    $Window.Resources["BrushHover"] = New-Brush $P.SurfaceHover

    $surfaceBrush = New-Brush $P.Surface
    $borderBrush = New-Brush $P.Border
    $dividerBrush = New-Brush $P.Divider
    $subtleBrush = New-Brush $P.SurfaceSubtle
    $insetBrush = New-Brush $P.SurfaceInset
    $inkPrimary = New-Brush $P.InkPrimary
    $inkSecondary = New-Brush $P.InkSecondary
    $inkMuted = New-Brush $P.InkMuted

    $PillView.Background = $surfaceBrush
    $PillView.BorderBrush = $borderBrush
    $PillShadow.Opacity = $P.ShadowOpacity
    $PillStatusText.Foreground = $inkPrimary
    $PillExpandIcon.Stroke = $inkSecondary
    $PillProgressContainer.Background = New-Brush $P.ProgressTrack

    $CardView.Background = $surfaceBrush
    $CardView.BorderBrush = $borderBrush
    $CardShadow.Opacity = $P.ShadowOpacity

    $LogoArc.Stroke = $inkPrimary
    $LogoStem.Stroke = $inkPrimary
    $CardTitle.Foreground = $inkPrimary
    $BtnLangText.Foreground = $inkSecondary
    $IconMoon.Stroke = $inkSecondary
    $IconSun.Stroke = $inkSecondary
    if ($resolved -eq "dark") {
        $IconSun.Visibility = [System.Windows.Visibility]::Visible
        $IconMoon.Visibility = [System.Windows.Visibility]::Collapsed
    } else {
        $IconSun.Visibility = [System.Windows.Visibility]::Collapsed
        $IconMoon.Visibility = [System.Windows.Visibility]::Visible
    }
    $IconCollapse.Stroke = $inkSecondary
    $IconHide.Stroke = $inkSecondary

    $Div1.Fill = $dividerBrush
    $Div2.Fill = $dividerBrush
    $Div3.Fill = $dividerBrush

    $LblTasksTitle.Foreground = $inkMuted
    $LblTasksCount.Foreground = $inkSecondary
    $BtnClearStale.Foreground = $inkSecondary
    $TasksBox.Background = $insetBrush
    $TasksBox.BorderBrush = $dividerBrush
    $TasksEmptyDot.Fill = $inkMuted
    $LblTasksEmpty.Foreground = $inkSecondary

    $LblMode.Foreground = $inkMuted
    $TrackMode.Background = $subtleBrush
    $LblAction.Foreground = $inkMuted
    $TrackAction.Background = $subtleBrush
    $LblGrace.Foreground = $inkMuted
    $TrackGrace.Background = $subtleBrush

    $LblOptIgnoreCancel.Foreground = $inkPrimary
    $LblOptTopmost.Foreground = $inkPrimary
    $LblFooter.Foreground = $inkMuted
    $BtnPreview.Foreground = $inkSecondary

    $CardProgressTrack.Background = New-Brush $P.ProgressTrack
    $BtnExecuteNow.Background = $subtleBrush
    $BtnExecuteNow.BorderBrush = $borderBrush
    $BtnExecuteNow.Foreground = $inkPrimary
}

function Render-UI {
    $cfg = $script:Config
    $st = $script:State
    $P = $Palettes[$script:CurrentTheme]

    $Window.Topmost = [bool]$cfg.alwaysOnTop

    # Extract active sessions
    $sessions = @()
    if ($st -and $st.activeSessions) {
        foreach ($prop in $st.activeSessions.PSObject.Properties) {
            if ($prop.Value) { $sessions += $prop.Value }
        }
    }
    $activeCount = $sessions.Count

    $cd = if ($st) { $st.countdown } else { $null }
    $cdActive = ($cd -and $cd.active -eq $true)
    $cdPreview = ($cdActive -and $cd.preview -eq $true)
    $armed = [bool]$cfg.armed

    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $remainSec = 0
    $progressFrac = 0.0
    if ($cdActive) {
        $executeAt = [double]$cd.executeAt
        $startedAt = [double]$cd.startedAt
        $totalMs = [Math]::Max(1000.0, ($executeAt - $startedAt))
        $remMs = [Math]::Max(0.0, ($executeAt - $nowMs))
        $remainSec = [int][Math]::Ceiling($remMs / 1000.0)
        $progressFrac = [Math]::Max(0.0, [Math]::Min(1.0, ($remMs / $totalMs)))
    }

    # Determine visual state & semantic dot
    $dotHex = $P.DotStandby
    $badgeBgHex = $P.SurfaceSubtle
    $badgeBorderHex = $P.Border
    $badgeInkHex = $P.InkSecondary
    $badgeLabel = Get-Text "badgeStandby"
    $shouldPulse = $false

    if ($cdActive) {
        $shouldPulse = $true
        if ($cdPreview) {
            $dotHex = $P.DotRunning
            $badgeBgHex = $P.PreviewBg
            $badgeBorderHex = $P.PreviewBorder
            $badgeInkHex = $P.PreviewInk
            $badgeLabel = Get-Text "badgePreview"
        } else {
            $dotHex = $P.DotCountdown
            $badgeBgHex = $P.CountdownBg
            $badgeBorderHex = $P.CountdownBorder
            $badgeInkHex = $P.CountdownInk
            $badgeLabel = Get-Text "badgeCountdown"
        }
    } elseif ($activeCount -gt 0) {
        $shouldPulse = $true
        $dotHex = $P.DotRunning
        $badgeBgHex = $P.PreviewBg
        $badgeBorderHex = $P.PreviewBorder
        $badgeInkHex = $P.PreviewInk
        $badgeLabel = Get-Text "badgeRunning"
    } elseif ($armed) {
        $dotHex = $P.DotArmed
        $badgeBgHex = $P.ArmedBg
        $badgeBorderHex = $P.ArmedBorder
        $badgeInkHex = $P.ArmedInk
        $badgeLabel = Get-Text "badgeArmed"
    }

    $dotBrush = New-Brush $dotHex
    $PillDot.Fill = $dotBrush
    $PillDotHalo.Fill = $dotBrush
    $BadgeDot.Fill = $dotBrush
    $LogoDot.Fill = $dotBrush
    $FooterDot.Fill = $dotBrush

    # Subtle breathing pulse
    if ($shouldPulse) {
        $script:PulsePhase = ($script:PulsePhase + 1) % 6
        $haloOps = @(0.16, 0.28, 0.38, 0.34, 0.24, 0.16)
        $PillDotHalo.Opacity = $haloOps[$script:PulsePhase]
    } else {
        $PillDotHalo.Opacity = 0.16
    }

    # Update Badge
    $StatusBadge.Background = New-Brush $badgeBgHex
    $StatusBadge.BorderBrush = New-Brush $badgeBorderHex
    $BadgeText.Foreground = New-Brush $badgeInkHex
    $BadgeText.Text = $badgeLabel

    # Update Pill Texts & Quick Button
    $actionLabel = Get-ActionLabel $(if ($cdActive -and $cd.action) { $cd.action } else { $cfg.action })
    if ($cdActive) {
        $timeStr = Format-Duration $remainSec
        $PillStatusText.FontFamily = New-Object System.Windows.Media.FontFamily("Cascadia Mono, Consolas, Segoe UI Variable Text, Microsoft YaHei UI")
        $PillStatusText.Text = if ($cdPreview) {
            Get-Text "pillPreview" @{ time = $timeStr }
        } else {
            Get-Text "pillCountdown" @{ time = $timeStr; action = $actionLabel }
        }
        $PillQuickBtn.Content = Get-Text "btnCancel"
        $PillQuickBtn.Background = New-Brush $P.CancelBtnBg
        $PillQuickBtn.BorderBrush = New-Brush $P.CountdownBorder
        $PillQuickBtn.Foreground = New-Brush $P.CountdownInk

        $PillProgressContainer.Visibility = [System.Windows.Visibility]::Visible
        $PillProgressFill.Background = $dotBrush
        $trackW = [Math]::Max(160.0, ($PillView.ActualWidth - 40.0))
        $PillProgressFill.Width = [Math]::Round($trackW * $progressFrac)
    } else {
        $PillStatusText.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI Variable Text, Segoe UI, Microsoft YaHei UI")
        $PillProgressContainer.Visibility = [System.Windows.Visibility]::Collapsed
        if ($activeCount -gt 0) {
            $PillStatusText.Text = if ($armed) {
                Get-Text "pillRunningArmed" @{ n = $activeCount }
            } else {
                Get-Text "pillRunning" @{ n = $activeCount }
            }
        } else {
            $PillStatusText.Text = if ($armed) { Get-Text "pillIdleArmed" } else { Get-Text "pillIdleDisarmed" }
        }

        if ($armed) {
            $PillQuickBtn.Content = Get-Text "btnArmed"
            $PillQuickBtn.Background = New-Brush $P.ArmedBg
            $PillQuickBtn.BorderBrush = New-Brush $P.ArmedBorder
            $PillQuickBtn.Foreground = New-Brush $P.ArmedInk
        } else {
            $PillQuickBtn.Content = Get-Text "btnArm"
            $PillQuickBtn.Background = New-Brush $P.SurfaceSubtle
            $PillQuickBtn.BorderBrush = New-Brush $P.Border
            $PillQuickBtn.Foreground = New-Brush $P.InkPrimary
        }
    }

    # Update Card Header Labels & Tooltips
    $CardTitle.Text = Get-Text "appName"
    $BtnLangText.Text = if ($cfg.language -eq "en") { "ZH" } else { "EN" }
    $BtnTheme.ToolTip = Get-Text "tooltipTheme"
    $BtnCollapse.ToolTip = Get-Text "tooltipCollapse"
    $BtnHide.ToolTip = Get-Text "tooltipHide"

    # Update Card Countdown Panel
    if ($cdActive) {
        $wasCollapsed = ($CountdownPanel.Visibility -ne [System.Windows.Visibility]::Visible)
        $CountdownPanel.Visibility = [System.Windows.Visibility]::Visible
        if ($cdPreview) {
            $CountdownPanel.Background = New-Brush $P.PreviewBg
            $CountdownPanel.BorderBrush = New-Brush $P.PreviewBorder
            $CountdownTimerText.Foreground = New-Brush $P.PreviewInk
            $CountdownSubtitle.Foreground = New-Brush $P.InkSecondary
            $CountdownSubtitle.Text = Get-Text "countdownPreviewSubtitle"
            $BtnCancelCountdown.Content = Get-Text "btnCancel"
        } else {
            $CountdownPanel.Background = New-Brush $P.CountdownBg
            $CountdownPanel.BorderBrush = New-Brush $P.CountdownBorder
            $CountdownTimerText.Foreground = New-Brush $P.CountdownInk
            $CountdownSubtitle.Foreground = New-Brush $P.InkSecondary
            $CountdownSubtitle.Text = Get-Text "countdownSubtitle" @{ action = $actionLabel }
            $BtnCancelCountdown.Content = Get-Text "btnCancelAction" @{ action = $actionLabel }
        }
        $CountdownTimerText.Text = Format-Duration $remainSec
        $CardProgressFill.Background = $dotBrush
        $cardTrackW = if ($CardProgressTrack.ActualWidth -gt 40) { $CardProgressTrack.ActualWidth } else { 274.0 }
        $CardProgressFill.Width = [Math]::Round($cardTrackW * $progressFrac)
        $BtnCancelCountdown.Background = New-Brush $P.CancelBtnBg
        $BtnCancelCountdown.BorderBrush = New-Brush $P.CountdownBorder
        $BtnCancelCountdown.Foreground = New-Brush $P.CountdownInk
        $BtnExecuteNow.Content = Get-Text "btnExecuteNow"
        if ($wasCollapsed -and $script:Expanded) {
            $Window.UpdateLayout()
            Snap-BottomRight
        }
    } else {
        $wasVisible = ($CountdownPanel.Visibility -eq [System.Windows.Visibility]::Visible)
        $CountdownPanel.Visibility = [System.Windows.Visibility]::Collapsed
        if ($wasVisible -and $script:Expanded) {
            $Window.UpdateLayout()
            Snap-BottomRight
        }
    }

    # Update Active Tasks List
    $LblTasksTitle.Text = Get-Text "sectionTasks"
    $LblTasksCount.Text = if ($activeCount -gt 0) { Get-Text "tasksCount" @{ n = $activeCount } } else { "0" }
    $BtnClearStale.Content = Get-Text "btnClearStale"
    $BtnClearStale.Visibility = if ($activeCount -gt 0) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    $LblTasksEmpty.Text = Get-Text "tasksEmpty"

    if ($activeCount -eq 0) {
        $TasksEmptyPanel.Visibility = [System.Windows.Visibility]::Visible
        $TasksScroll.Visibility = [System.Windows.Visibility]::Collapsed
    } else {
        $TasksEmptyPanel.Visibility = [System.Windows.Visibility]::Collapsed
        $TasksScroll.Visibility = [System.Windows.Visibility]::Visible
        $TasksListPanel.Children.Clear()
        $idx = 0
        foreach ($s in $sessions) {
            $row = New-Object System.Windows.Controls.Grid
            if ($idx -gt 0) { $row.Margin = New-Object System.Windows.Thickness(0,7,0,0) }
            $c0 = New-Object System.Windows.Controls.ColumnDefinition; $c0.Width = [System.Windows.GridLength]::Auto
            $c1 = New-Object System.Windows.Controls.ColumnDefinition; $c1.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
            $c2 = New-Object System.Windows.Controls.ColumnDefinition; $c2.Width = [System.Windows.GridLength]::Auto
            $c3 = New-Object System.Windows.Controls.ColumnDefinition; $c3.Width = [System.Windows.GridLength]::Auto
            $row.ColumnDefinitions.Add($c0); $row.ColumnDefinitions.Add($c1); $row.ColumnDefinitions.Add($c2); $row.ColumnDefinitions.Add($c3)

            $dot = New-Object System.Windows.Shapes.Ellipse
            $dot.Width = 5; $dot.Height = 5
            $dot.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $dot.Margin = New-Object System.Windows.Thickness(0,0,7,0)
            $dot.Fill = New-Brush $(if ($s.status -eq "waiting_background") { $P.DotArmed } else { $P.DotRunning })
            [System.Windows.Controls.Grid]::SetColumn($dot, 0)

            $lbl = New-Object System.Windows.Controls.TextBlock
            $lbl.Text = if ($s.label) { [string]$s.label } else { [string]$s.conversationId }
            $lbl.FontSize = 12
            $lbl.Foreground = New-Brush $P.InkPrimary
            $lbl.TextTrimming = [System.Windows.TextTrimming]::CharacterEllipsis
            $lbl.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $lbl.Margin = New-Object System.Windows.Thickness(0,0,8,0)
            [System.Windows.Controls.Grid]::SetColumn($lbl, 1)

            $stKey = switch ($s.status) {
                "waiting_background" { "statusBackground" }
                "running_tool"       { "statusTool" }
                default              { "statusThinking" }
            }
            $tag = New-Object System.Windows.Controls.TextBlock
            $tag.Text = Get-Text $stKey
            $tag.FontSize = 10.5
            $tag.Foreground = New-Brush $P.InkMuted
            $tag.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            $tag.Margin = New-Object System.Windows.Thickness(0,0,8,0)
            [System.Windows.Controls.Grid]::SetColumn($tag, 2)

            $startedAtMs = if ($s.startedAt) { [double]$s.startedAt } else { $nowMs }
            $elapsedSec = [int][Math]::Max(0, [Math]::Floor(($nowMs - $startedAtMs) / 1000.0))
            $dur = New-Object System.Windows.Controls.TextBlock
            $dur.Text = Format-Duration $elapsedSec
            $dur.FontFamily = New-Object System.Windows.Media.FontFamily("Cascadia Mono, Consolas")
            $dur.FontSize = 10.5
            $dur.Foreground = New-Brush $P.InkSecondary
            $dur.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
            [System.Windows.Controls.Grid]::SetColumn($dur, 3)

            $row.Children.Add($dot) | Out-Null
            $row.Children.Add($lbl) | Out-Null
            $row.Children.Add($tag) | Out-Null
            $row.Children.Add($dur) | Out-Null
            $TasksListPanel.Children.Add($row) | Out-Null
            $idx++
        }
    }

    # Controls Labels & Segmented States
    $LblMode.Text = Get-Text "labelMode"
    $SegModeOff.Content = Get-Text "modeOff"
    $SegModeOnce.Content = Get-Text "modeOnce"
    $SegModeCont.Content = Get-Text "modeContinuous"
    $activeModeBtn = if (-not $armed) { $SegModeOff } elseif ($cfg.mode -eq "continuous") { $SegModeCont } else { $SegModeOnce }
    Style-SegmentGroup @($SegModeOff, $SegModeOnce, $SegModeCont) $activeModeBtn $P

    $LblAction.Text = Get-Text "labelAction"
    $SegActShutdown.Content = Get-Text "actionShutdown"
    $SegActHibernate.Content = Get-Text "actionHibernate"
    $SegActSleep.Content = Get-Text "actionSleep"
    $activeActBtn = switch ($cfg.action) {
        "hibernate" { $SegActHibernate }
        "sleep"     { $SegActSleep }
        default     { $SegActShutdown }
    }
    Style-SegmentGroup @($SegActShutdown, $SegActHibernate, $SegActSleep) $activeActBtn $P

    $LblGrace.Text = Get-Text "labelGrace"
    $gSec = [int]$cfg.graceSeconds
    $activeGraceBtn = switch ($gSec) {
        30  { $SegGrace30 }
        60  { $SegGrace60 }
        300 { $SegGrace300 }
        default { if ($gSec -eq 120) { $SegGrace120 } else { $null } }
    }
    Style-SegmentGroup @($SegGrace30, $SegGrace60, $SegGrace120, $SegGrace300) $activeGraceBtn $P

    # Switches
    $LblOptIgnoreCancel.Text = Get-Text "optIgnoreCancel"
    $LblOptTopmost.Text = Get-Text "optAlwaysOnTop"
    Style-Switch $SwitchIgnoreCancel $ThumbIgnoreCancel ([bool]$cfg.ignoreUserCancel) $P
    Style-Switch $SwitchTopmost $ThumbTopmost ([bool]$cfg.alwaysOnTop) $P

    # Footer
    if ($st -and $st.lastEvent -and $st.lastEvent.timestamp) {
        $dt = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$st.lastEvent.timestamp).ToLocalTime()
        $LblFooter.Text = Get-Text "footerLastEvent" @{ time = $dt.ToString("HH:mm:ss") }
    } else {
        $LblFooter.Text = Get-Text "footerReady"
    }
    $BtnPreview.Content = Get-Text "btnPreview"

    # Refresh System Tray icon & tooltip when status changes
    $trayKey = "$($script:CurrentTheme)|$dotHex"
    if ($script:TrayIcon -and $trayKey -ne $script:TrayIconState) {
        $script:TrayIconState = $trayKey
        try {
            $oldIcon = $script:TrayIcon.Icon
            $script:TrayIcon.Icon = Create-TrayIcon -DotHex $dotHex -IsDark ($script:CurrentTheme -eq "dark")
            if ($oldIcon) { $oldIcon.Dispose() }
        } catch {}
    }
    if ($script:TrayIcon) {
        $tip = "Auto Shutdown - $($PillStatusText.Text)"
        if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
        $script:TrayIcon.Text = $tip
    }
}

function Sync-FromDisk {
    # Check wakeup signal from another launch
    if (Test-Path $WakeupSignalPath) {
        try {
            $sig = [System.IO.File]::ReadAllText($WakeupSignalPath, [System.Text.Encoding]::UTF8).Trim()
            if ($sig -and $sig -ne $script:LastWakeupStamp) {
                $script:LastWakeupStamp = $sig
                $Window.Show()
                $Window.Activate()
                if ($sig.StartsWith("expand:")) {
                    Set-Expanded $true
                } else {
                    Snap-BottomRight
                }
            }
        } catch {}
    }

    $diskCfg = Read-JsonFile $ConfigPath
    if ($diskCfg) { $script:Config = $diskCfg }
    $diskState = Read-JsonFile $StatePath
    if ($diskState) { $script:State = $diskState }

    # Auto-reveal from tray if a real countdown just started
    if ($script:State -and $script:State.countdown -and $script:State.countdown.active -eq $true -and -not $Window.IsVisible) {
        $Window.Show()
        Snap-BottomRight
    }

    Apply-Theme
    Render-UI
}

# ==================== WIRE INTERACTIONS ====================

# Dragging support on pill & card header
$dragHandler = {
    param($s, $e)
    if ($e.ChangedButton -eq [System.Windows.Input.MouseButton]::Left) {
        if ($e.ClickCount -eq 2) {
            $script:UserDragged = $false
            Snap-BottomRight
            return
        }
        try {
            $Window.DragMove()
            $script:UserDragged = $true
            $script:AnchorRight = $Window.Left + $Window.ActualWidth
            $script:AnchorBottom = $Window.Top + $Window.ActualHeight
        } catch {}
    }
}
$PillDragArea.Add_MouseLeftButtonDown($dragHandler)
$CardDragHeader.Add_MouseLeftButtonDown($dragHandler)

# Pill buttons
$PillExpandBtn.Add_Click({ Set-Expanded $true })
$PillQuickBtn.Add_Click({
    if ($script:State -and $script:State.countdown -and $script:State.countdown.active -eq $true) {
        $script:State.countdown.active = $false
        Render-UI
        Invoke-CtlAsync @("cancel")
    } elseif ($script:Config.armed) {
        $script:Config.armed = $false
        Render-UI
        Invoke-CtlAsync @("disarm")
    } else {
        $script:Config.armed = $true
        if (-not $script:Config.mode) { $script:Config.mode = "once" }
        Render-UI
        Invoke-CtlAsync @("arm", "--mode", $script:Config.mode, "--ui", "false")
    }
})

# Card header buttons
$BtnCollapse.Add_Click({ Set-Expanded $false })
$BtnHide.Add_Click({ $Window.Hide() })
$BtnTheme.Add_Click({
    $next = if ($script:CurrentTheme -eq "dark") { "light" } else { "dark" }
    $script:Config.theme = $next
    Apply-Theme
    Render-UI
    Invoke-CtlAsync @("config", "--theme", $next)
})
$BtnLang.Add_Click({
    $next = if ($script:Config.language -eq "en") { "zh-CN" } else { "en" }
    $script:Config.language = $next
    Render-UI
    Invoke-CtlAsync @("config", "--lang", $next)
})

# Countdown buttons
$BtnCancelCountdown.Add_Click({
    if ($script:State -and $script:State.countdown) { $script:State.countdown.active = $false }
    Render-UI
    Invoke-CtlAsync @("cancel")
})
$BtnExecuteNow.Add_Click({
    Invoke-CtlAsync @("execute-now")
})

# Clear stale sessions
$BtnClearStale.Add_Click({
    $script:State.activeSessions = [PSCustomObject]@{}
    Render-UI
    Invoke-CtlAsync @("clear-stale")
})

# Mode segmented buttons
$SegModeOff.Add_Click({
    $script:Config.armed = $false
    Render-UI
    Invoke-CtlAsync @("disarm")
})
$SegModeOnce.Add_Click({
    $script:Config.armed = $true
    $script:Config.mode = "once"
    Render-UI
    Invoke-CtlAsync @("arm", "--mode", "once", "--ui", "false")
})
$SegModeCont.Add_Click({
    $script:Config.armed = $true
    $script:Config.mode = "continuous"
    Render-UI
    Invoke-CtlAsync @("arm", "--mode", "continuous", "--ui", "false")
})

# Action segmented buttons
$SegActShutdown.Add_Click({
    $script:Config.action = "shutdown"
    Render-UI
    Invoke-CtlAsync @("config", "--action", "shutdown")
})
$SegActHibernate.Add_Click({
    $script:Config.action = "hibernate"
    Render-UI
    Invoke-CtlAsync @("config", "--action", "hibernate")
})
$SegActSleep.Add_Click({
    $script:Config.action = "sleep"
    Render-UI
    Invoke-CtlAsync @("config", "--action", "sleep")
})

# Grace segmented buttons
$SegGrace30.Add_Click({  $script:Config.graceSeconds = 30;  Render-UI; Invoke-CtlAsync @("config", "--grace", "30") })
$SegGrace60.Add_Click({  $script:Config.graceSeconds = 60;  Render-UI; Invoke-CtlAsync @("config", "--grace", "60") })
$SegGrace120.Add_Click({ $script:Config.graceSeconds = 120; Render-UI; Invoke-CtlAsync @("config", "--grace", "120") })
$SegGrace300.Add_Click({ $script:Config.graceSeconds = 300; Render-UI; Invoke-CtlAsync @("config", "--grace", "300") })

# Switches
$SwitchIgnoreCancel.Add_MouseLeftButtonUp({
    $next = -not [bool]$script:Config.ignoreUserCancel
    $script:Config.ignoreUserCancel = $next
    Render-UI
    Invoke-CtlAsync @("config", "--ignore-cancel", $(if ($next) { "true" } else { "false" }))
})
$SwitchTopmost.Add_MouseLeftButtonUp({
    $next = -not [bool]$script:Config.alwaysOnTop
    $script:Config.alwaysOnTop = $next
    Render-UI
    Invoke-CtlAsync @("config", "--always-on-top", $(if ($next) { "true" } else { "false" }))
})

# Safe dry-run preview button
$BtnPreview.Add_Click({
    Invoke-CtlAsync @("preview", "--seconds", "15")
})

# ==================== SYSTEM TRAY ICON ====================
$script:TrayIcon = $null
if ([string]::IsNullOrWhiteSpace($CapturePath)) {
    $script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:TrayIcon.Visible = $true

    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip
    $miShow = $trayMenu.Items.Add((Get-Text "trayShow"))
    $miReset = $trayMenu.Items.Add((Get-Text "trayResetPos"))
    $trayMenu.Items.Add("-") | Out-Null
    $miArm = $trayMenu.Items.Add((Get-Text "trayArmOnce"))
    $miDisarm = $trayMenu.Items.Add((Get-Text "trayDisarm"))
    $miCancel = $trayMenu.Items.Add((Get-Text "trayCancel"))
    $trayMenu.Items.Add("-") | Out-Null
    $miQuit = $trayMenu.Items.Add((Get-Text "trayQuit"))

    $miShow.Add_Click({
        if ($Window.IsVisible) { $Window.Hide() } else { $Window.Show(); $Window.Activate(); Snap-BottomRight }
    })
    $miReset.Add_Click({
        $script:UserDragged = $false
        $Window.Show(); $Window.Activate(); Snap-BottomRight
    })
    $miArm.Add_Click({ Invoke-CtlAsync @("arm", "--mode", "once", "--ui", "false") })
    $miDisarm.Add_Click({ Invoke-CtlAsync @("disarm") })
    $miCancel.Add_Click({ Invoke-CtlAsync @("cancel") })
    $miQuit.Add_Click({
        if ($script:TrayIcon) { $script:TrayIcon.Visible = $false; $script:TrayIcon.Dispose() }
        $Window.Close()
    })

    $script:TrayIcon.ContextMenuStrip = $trayMenu
    $script:TrayIcon.Add_MouseClick({
        param($s, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            if ($Window.IsVisible) { $Window.Hide() } else { $Window.Show(); $Window.Activate(); Snap-BottomRight }
        }
    })
}

# ==================== TIMERS & LIFECYCLE ====================
$Timer = New-Object System.Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromMilliseconds(500)
$Timer.Add_Tick({ Sync-FromDisk })

$Window.Add_Loaded({
    Sync-FromDisk
    Set-Expanded $script:Expanded
    $Timer.Start()

    # Optional visual capture mode for automated screenshot QA
    if (-not [string]::IsNullOrWhiteSpace($CapturePath)) {
        $capTimer = New-Object System.Windows.Threading.DispatcherTimer
        $capTimer.Interval = [TimeSpan]::FromMilliseconds([Math]::Max(300, $CaptureDelayMs))
        $capTimer.Add_Tick({
            $capTimer.Stop()
            try {
                $Window.UpdateLayout()
                $src = [System.Windows.PresentationSource]::FromVisual($Window)
                $dpiX = if ($src) { $src.CompositionTarget.TransformToDevice.M11 } else { 1.0 }
                $dpiY = if ($src) { $src.CompositionTarget.TransformToDevice.M22 } else { 1.0 }
                $wPx = [int][Math]::Ceiling($Window.ActualWidth * $dpiX)
                $hPx = [int][Math]::Ceiling($Window.ActualHeight * $dpiY)
                $xPx = [int][Math]::Round($Window.Left * $dpiX)
                $yPx = [int][Math]::Round($Window.Top * $dpiY)

                $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(
                    $wPx, $hPx, (96.0 * $dpiX), (96.0 * $dpiY), [System.Windows.Media.PixelFormats]::Pbgra32
                )
                $rtb.Render($Window)
                $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
                $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
                $dir = Split-Path -Parent $CapturePath
                if ($dir -and !(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                $fs = [System.IO.File]::Open($CapturePath, [System.IO.FileMode]::Create)
                $encoder.Save($fs)
                $fs.Close()
            } finally {
                $Window.Close()
            }
        })
        $capTimer.Start()
    }
})

$Window.Add_Closed({
    $Timer.Stop()
    if ($script:TrayIcon) {
        $script:TrayIcon.Visible = $false
        $script:TrayIcon.Dispose()
    }
    if ($script:Mutex) {
        try { $script:Mutex.ReleaseMutex() } catch {}
        $script:Mutex.Dispose()
    }
})

$Window.ShowDialog() | Out-Null
