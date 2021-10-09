unit uMultiDisplay;

interface

uses System.Generics.Collections, Winapi.Windows, System.SysUtils,
  Winapi.MultiMon, System.Win.Registry, System.Classes, Winapi.Messages,
  System.Generics.Defaults, System.Messaging;

type
  TMonitorOrientation = (moUnknown, moLandscape, moPortrait, moLandscapeFlipped,
    moPortraitFlipped);

const
  MONITOR_ORIENTATIONS: array [Low(TMonitorOrientation)
    .. High(TMonitorOrientation)] of string = ('Не изменять', 'Альбомная (0°)',
    'Портретная (90°)', 'Альбомная перевернутая (180°)',
    'Портретная перевернутая (270°)');

const
  ENUM_CURRENT_SETTINGS = DWORD(-1);

type
  _devicemode = record
    dmDeviceName: array [0 .. CCHDEVICENAME - 1] of
{$IFDEF UNICODE}WideChar{$ELSE}AnsiChar{$ENDIF};
    dmSpecVersion: WORD;
    dmDriverVersion: WORD;
    dmSize: WORD;
    dmDriverExtra: WORD;
    dmFields: DWORD;

    union1: record
      case Integer of
        0:
          (dmOrientation: SmallInt;
            dmPaperSize: SmallInt;
            dmPaperLength: SmallInt;
            dmPaperWidth: SmallInt;
            dmScale: SmallInt;
            dmCopies: SmallInt;
            dmDefaultSource: SmallInt;
            dmPrintQuality: SmallInt);
        1:
          (dmPosition: TPointL;
            dmDisplayOrientation: DWORD;
            dmDisplayFixedOutput: DWORD);
    end;

    dmColor: ShortInt;
    dmDuplex: ShortInt;
    dmYResolution: ShortInt;
    dmTTOption: ShortInt;
    dmCollate: ShortInt;
    dmFormName: array [0 .. CCHFORMNAME - 1] of
{$IFDEF UNICODE}WideChar{$ELSE}AnsiChar{$ENDIF};
    dmLogPixels: WORD;
    dmBitsPerPel: DWORD;
    dmPelsWidth: DWORD;
    dmPelsHeight: DWORD;
    dmDiusplayFlags: DWORD;
    dmDisplayFrequency: DWORD;
    dmICMMethod: DWORD;
    dmICMIntent: DWORD;
    dmMediaType: DWORD;
    dmDitherType: DWORD;
    dmReserved1: DWORD;
    dmReserved2: DWORD;
    dmPanningWidth: DWORD;
    dmPanningHeight: DWORD;
  end;

  devicemode = _devicemode;
  Pdevicemode = ^devicemode;

type
  TMonitorModeItem = record
  public
    Width: DWORD;
    Height: DWORD;
    function Resolution: string;
  end;

  TMonitorModeList = class(TList<TMonitorModeItem>)
  public
    constructor Create; reintroduce;
  end;

  TSettingComparer = class(TComparer<TMonitorModeItem>)
  public
    function Compare(const Left, Right: TMonitorModeItem): Integer; override;
  end;

  TMonitorDevice = class
  private
    procedure UpdateModes;
  public
    Handle: HMONITOR;
    DeviceName: string;
    FriendlyName: string;
    Modes: TMonitorModeList;
    WorkareaRect: TRect;
  public
    constructor Create(const ADeviceName, AFriendlyName: string;
      AWorkArea: TRect; const AHandle: HMONITOR);
    destructor Destroy; override;
  public
    procedure SetMode(AModeNum: Integer); overload;
    function SetMode(AWidth, AHeight: Integer;
      AOrientation: TMonitorOrientation): Boolean; overload;
    function SetMode(const AResolution: string;
      AOrientation: TMonitorOrientation): Boolean; overload;
    function SetResolution(AWidth, AHeight: Integer): Boolean; overload;
    function SetResolution(const AResolution: string): Boolean; overload;
    function SetOrientation(AOrientation: TMonitorOrientation): Boolean;
    function FindModeByResolution(const AResilution: string;
      var AModeItem: TMonitorModeItem): Boolean;
  end;

  TMultiDisplay = class
  private
    FMonitorList: TObjectList<TMonitorDevice>;
    FOnUpdateMonitorList: TNotifyEvent;
  private
    procedure UpdateMonitorList(ASendNotifications: Boolean);
  public
    constructor Create;
    destructor Destroy; override;
  public
    function SetMode(const ADevice, AResolution: string;
      AOrientation: TMonitorOrientation): Boolean;
    function SetResolution(const ADevice: string; AWidth, AHeight: Integer)
      : Boolean; overload;
    function SetResolution(const ADevice, AResolution: string)
      : Boolean; overload;
    function SetOrientation(const ADevice: string;
      AOrientation: TMonitorOrientation): Boolean;
    function FindMonitorByDeviceName(const ADeviceName: string;
      var AMonitorDevice: TMonitorDevice): Boolean;
  public
    property MonitorList: TObjectList<TMonitorDevice> read FMonitorList;
    property OnUpdateMonitorList: TNotifyEvent read FOnUpdateMonitorList
      write FOnUpdateMonitorList;
  end;

implementation

function SplitResolution(const AResilution: string;
  var AWidth, AHeight: Integer): Boolean;
var
  LResolution: TArray<string>;
begin
  Result := False;

  LResolution := AResilution.Split(['x']);
  if Length(LResolution) < 2 then
    Exit;
  if not TryStrToInt(LResolution[0], AWidth) then
    Exit;
  if not TryStrToInt(LResolution[1], AHeight) then
    Exit;

  Result := True;
end;

procedure RaiseChangeDisplaySettingsError(AError: Integer);
var
  LMessage: string;
begin
  case AError of
    DISP_CHANGE_BADFLAGS:
      LMessage := 'Был передан недопустимый набор флагов.';
    DISP_CHANGE_BADMODE:
      LMessage := 'Графический режим не поддерживается.';
    DISP_CHANGE_BADPARAM:
      LMessage :=
        'Был передан недопустимый параметр. Он может включать недопустимый флаг или комбинацию флагов.';
    DISP_CHANGE_FAILED:
      LMessage := 'Драйвер дисплея отказал в указанном графическом режиме.';
    DISP_CHANGE_NOTUPDATED:
      LMessage := 'Невозможно записать настройки в реестр.';
    DISP_CHANGE_RESTART:
      LMessage :=
        'Для работы графического режима необходимо перезагрузить компьютер.';
  else
    LMessage := Format('Неизвестная ошибка: ', [AError])
  end;

  MessageBox(0, PWideChar(LMessage), PWideChar('Ошибка'),
    MB_OK or MB_ICONWARNING);
end;

function GetDeviceModelName(const DeviceID: string): string;
const
  KEY = '\SYSTEM\CurrentControlSet\Enum\DISPLAY\';
type
  IBM_STRING = type Ansistring(1253);
var
  I, J, K: Integer;
  LRegistry: TRegistry;
  LMonitorName: IBM_STRING;
  LSubKeysNames: TStringList;
  LDeviceIDSplit: TArray<String>;
  LEdid: array [0 .. 127] of Byte;
  LDriver: string;
begin
  LDeviceIDSplit := DeviceID.Split(['\']);
  if Length(LDeviceIDSplit) < 3 then
    Exit;
  LDriver := '';
  for I := 2 to High(LDeviceIDSplit) do
    LDriver := LDriver + '\' + LDeviceIDSplit[I];
  System.Delete(LDriver, 1, 1);

  LSubKeysNames := TStringList.Create;
  LRegistry := TRegistry.Create(KEY_READ);
  LRegistry.RootKey := HKEY_LOCAL_MACHINE;
  try
    try
      LRegistry.OpenKeyReadOnly(KEY);
      LRegistry.GetKeyNames(LSubKeysNames);
    finally
      LRegistry.CloseKey;
    end;
    if LSubKeysNames.IndexOf(LDeviceIDSplit[1]) < 0 then
      Exit;
    try
      LRegistry.OpenKeyReadOnly(KEY + LDeviceIDSplit[1]);
      LRegistry.GetKeyNames(LSubKeysNames);
    finally
      LRegistry.CloseKey;
    end;

    for I := 0 to LSubKeysNames.Count - 1 do
    begin
      try
        if LRegistry.OpenKeyReadOnly(KEY + LDeviceIDSplit[1] + '\' +
          LSubKeysNames[I]) then
        begin
          if LRegistry.ReadString('Driver') <> LDriver then
            Continue;
          LRegistry.CloseKey;
          if LRegistry.OpenKeyReadOnly(KEY + LDeviceIDSplit[1] + '\' +
            LSubKeysNames[I] + '\' + 'Device Parameters') then
          begin
            LRegistry.ReadBinaryData('EDID', LEdid, 128);
            LRegistry.CloseKey;
          end;
          for J := 0 to 3 do
          begin
            if (LEdid[54 + 18 * J] = 0) and (LEdid[55 + 18 * J] = 0) and
              (LEdid[56 + 18 * J] = 0) and (LEdid[57 + 18 * J] = $FC) and
              (LEdid[58 + 18 * J] = 0) then
            begin
              K := 0;
              while (LEdid[59 + 18 * J + K] <> $A) and (K < 13) do
                Inc(K);
              SetString(LMonitorName, PAnsiChar(@LEdid[59 + 18 * J]), K);
              Result := string(LMonitorName);
              Break;
            end;
          end;
        end;
      finally
        LRegistry.CloseKey;
      end;
    end;
  finally
    LRegistry.Free;
    LSubKeysNames.Free;
  end;
end;

{ TMultiDisplayModule }

constructor TMultiDisplay.Create;
begin
  FMonitorList := TObjectList<TMonitorDevice>.Create;
  UpdateMonitorList(False);
end;

destructor TMultiDisplay.Destroy;
begin
  FreeAndNil(FMonitorList);
  inherited;
end;

function TMultiDisplay.FindMonitorByDeviceName(const ADeviceName: string;
  var AMonitorDevice: TMonitorDevice): Boolean;
var
  I: Integer;
begin
  AMonitorDevice := nil;

  try
    for I := 0 to Pred(MonitorList.Count) do
      if SameText(MonitorList[I].DeviceName, ADeviceName) then
      begin
        AMonitorDevice := MonitorList[I];
        Break;
      end;
  finally
    Result := Assigned(AMonitorDevice);
  end;
end;

function TMultiDisplay.SetMode(const ADevice, AResolution: string;
  AOrientation: TMonitorOrientation): Boolean;
var
  LMonitor: TMonitorDevice;
begin
  Result := FindMonitorByDeviceName(ADevice, LMonitor);
  if not Result then
    Exit;

  Result := LMonitor.SetMode(AResolution, AOrientation);
  if Result then
    UpdateMonitorList(True);
end;

function TMultiDisplay.SetOrientation(const ADevice: string;
  AOrientation: TMonitorOrientation): Boolean;
var
  LMonitor: TMonitorDevice;
begin
  Result := FindMonitorByDeviceName(ADevice, LMonitor);
  if not Result then
    Exit;

  Result := LMonitor.SetOrientation(AOrientation);
  if Result then
    UpdateMonitorList(True);
end;

function TMultiDisplay.SetResolution(const ADevice,
  AResolution: string): Boolean;
begin
  Result := SetResolution(ADevice, AResolution);
end;

function TMultiDisplay.SetResolution(const ADevice: string;
  AWidth, AHeight: Integer): Boolean;
var
  LMonitor: TMonitorDevice;
begin
  Result := FindMonitorByDeviceName(ADevice, LMonitor);
  if not Result then
    Exit;

  Result := LMonitor.SetResolution(AWidth, AHeight);
  if Result then
    UpdateMonitorList(True);
end;

function EnumMonitorsProc(hm: HMONITOR; dc: HDC; R: PRect; Data: Pointer)
  : Boolean; stdcall;
var
  Sender: TMultiDisplay;
  MonInfo: TMonitorInfoEx;
  LDisplayDevice: TDisplayDevice;
  LFriendlyName: string;
begin
  Sender := TMultiDisplay(Data);
  MonInfo.cbSize := SizeOf(MonInfo);
  if GetMonitorInfo(hm, @MonInfo) then
  begin
    if Sender.FMonitorList = nil then
      Sender.FMonitorList := TObjectList<TMonitorDevice>.Create;

    ZeroMemory(@LDisplayDevice, SizeOf(LDisplayDevice));
    LDisplayDevice.cb := SizeOf(LDisplayDevice);
    EnumDisplayDevices(@MonInfo.szDevice[0], 0, LDisplayDevice, 0);
    LFriendlyName := Format('%s (%s)', [LDisplayDevice.DeviceString,
      GetDeviceModelName(LDisplayDevice.DeviceID)]);

    Sender.FMonitorList.Add(TMonitorDevice.Create(MonInfo.szDevice,
      LFriendlyName, MonInfo.rcWork, hm));
  end;
  Result := True;
end;

procedure TMultiDisplay.UpdateMonitorList(ASendNotifications: Boolean);
begin
  FMonitorList.Clear;
  EnumDisplayMonitors(0, nil, @EnumMonitorsProc, Winapi.Windows.LPARAM(Self));
  if ASendNotifications then
  begin
    if Assigned(FOnUpdateMonitorList) then
      FOnUpdateMonitorList(Self);
  end;
end;

{ TMontor }

constructor TMonitorDevice.Create(const ADeviceName, AFriendlyName: string;
  AWorkArea: TRect; const AHandle: HMONITOR);
begin
  DeviceName := ADeviceName;
  FriendlyName := AFriendlyName;
  WorkareaRect := AWorkArea;
  Handle := AHandle;

  UpdateModes;
end;

destructor TMonitorDevice.Destroy;
begin
  FreeAndNil(Modes);
  inherited;
end;

function TMonitorDevice.FindModeByResolution(const AResilution: string;
  var AModeItem: TMonitorModeItem): Boolean;
var
  LWidth: Integer;
  LHeight: Integer;
  LResolution: TArray<string>;
  I: Integer;
begin
  LResolution := AResilution.Split(['x']);
  if Length(LResolution) < 2 then
    Exit(False);
  if not TryStrToInt(LResolution[0], LWidth) then
    Exit(False);
  if not TryStrToInt(LResolution[1], LHeight) then
    Exit(False);

  for I := 0 to Pred(Modes.Count) do
    if (Modes[I].Width = DWORD(LWidth)) and (Modes[I].Height = DWORD(LHeight))
    then
    begin
      AModeItem := Modes[I];
      Exit(True);
    end;

  Exit(False);
end;

procedure TMonitorDevice.UpdateModes;
var
  I: Integer;
  LDevMode: TDevMode;
  LMode: TMonitorModeItem;
  LTemp: DWORD;
begin
  if not Assigned(Modes) then
    Modes := TMonitorModeList.Create
  else
    Modes.Clear;

  I := 0;
  while EnumDisplaySettings(PChar(DeviceName), I, LDevMode) do
  begin
    with LDevMode do
    begin
      if Pdevicemode(@LDevMode)^.union1.dmDisplayOrientation in [1, 3] then
      begin
        LTemp := LDevMode.dmPelsHeight;
        LDevMode.dmPelsHeight := LDevMode.dmPelsWidth;
        LDevMode.dmPelsWidth := LTemp;
      end;

      LMode.Width := dmPelsWidth;
      LMode.Height := dmPelsHeight;
      if Modes.IndexOf(LMode) < 0 then
        Modes.Add(LMode);
    end;
    Inc(I);
  end;

  Modes.Sort;
end;

procedure TMonitorDevice.SetMode(AModeNum: Integer);
var
  LResult: Integer;
  LDevMode: TDeviceMode;
begin
  ZeroMemory(@LDevMode, SizeOf(LDevMode));
  if EnumDisplaySettings(PChar(DeviceName), AModeNum, LDevMode) then
  begin
    // LDevMode.dmFields := DM_PELSWIDTH or DM_PELSHEIGHT;
    LResult := ChangeDisplaySettingsEx(PChar(DeviceName), LDevMode, 0, 0, nil);
    if LResult <> DISP_CHANGE_SUCCESSFUL then
      RaiseChangeDisplaySettingsError(LResult);

    SendMessage(HWND_BROADCAST, WM_DISPLAYCHANGE, SPI_SETNONCLIENTMETRICS, 0);
  end;
end;

function TMonitorDevice.SetMode(AWidth, AHeight: Integer;
  AOrientation: TMonitorOrientation): Boolean;
var
  LDevMode: TDevMode;
  LResult: Integer;
  LOrientation: Integer;
  LChangeResolution, LChangeOrientation: Boolean;
  LWidth, LHeight: DWORD;
begin
  Result := False;
  LOrientation := Ord(AOrientation) - 1;

  ZeroMemory(@LDevMode, SizeOf(LDevMode));
  if EnumDisplaySettings(PChar(DeviceName), ENUM_CURRENT_SETTINGS, LDevMode)
  then
  begin
    LChangeResolution := ((AWidth > 0) or (AHeight > 0)) and
      ((LDevMode.dmPelsHeight <> DWORD(AHeight)) or
      (LDevMode.dmPelsWidth <> DWORD(AWidth)));
    LChangeOrientation := (AOrientation <> moUnknown) and
      (Pdevicemode(@LDevMode)^.union1.dmDisplayOrientation <>
      DWORD(LOrientation));

    Result := LChangeResolution or LChangeOrientation;
    if not Result then
      Exit;

    begin
      if LChangeResolution then
      begin
        LWidth := AWidth;
        LHeight := AHeight;
      end
      else
      begin
        LWidth := LDevMode.dmPelsWidth;
        LHeight := LDevMode.dmPelsHeight;
      end;

      if LChangeOrientation then
        Pdevicemode(@LDevMode)^.union1.dmDisplayOrientation :=
          DWORD(LOrientation);

      if Pdevicemode(@LDevMode)^.union1.dmDisplayOrientation in [0, 2] then
      begin
        LDevMode.dmPelsWidth := LWidth;
        LDevMode.dmPelsHeight := LHeight;
      end
      else
      begin
        LDevMode.dmPelsWidth := LHeight;
        LDevMode.dmPelsHeight := LWidth;
      end;

      LResult := ChangeDisplaySettingsEx(PChar(DeviceName), LDevMode,
        0, 0, nil);
      Result := LResult = DISP_CHANGE_SUCCESSFUL;
      if not Result then
        RaiseChangeDisplaySettingsError(LResult)
      else
        SendMessage(HWND_BROADCAST, WM_DISPLAYCHANGE,
          SPI_SETNONCLIENTMETRICS, 0);
    end;
  end;
end;

function TMonitorDevice.SetMode(const AResolution: string;
  AOrientation: TMonitorOrientation): Boolean;
var
  LWidth, LHeight: Integer;
begin
  if not SplitResolution(AResolution, LWidth, LHeight) then
  begin
    LWidth := 0;
    LHeight := 0;
  end;

  Result := SetMode(LWidth, LHeight, AOrientation);
end;

function TMonitorDevice.SetOrientation(AOrientation
  : TMonitorOrientation): Boolean;
var
  LDevMode: TDevMode;
  LTemp: DWORD;
  LResult: Integer;
  LOrientation: Integer;
begin
  Result := False;
  if AOrientation = moUnknown then
    Exit;

  LOrientation := Ord(AOrientation) - 1;

  ZeroMemory(@LDevMode, SizeOf(LDevMode));
  if EnumDisplaySettings(PChar(DeviceName), ENUM_CURRENT_SETTINGS, LDevMode)
  then
  begin
    if Odd(Pdevicemode(@LDevMode)^.union1.dmDisplayOrientation) <>
      Odd(LOrientation) then
    begin
      LTemp := LDevMode.dmPelsHeight;
      LDevMode.dmPelsHeight := LDevMode.dmPelsWidth;
      LDevMode.dmPelsWidth := LTemp;
    end;

    if Pdevicemode(@LDevMode)^.union1.dmDisplayOrientation <> DWORD(LOrientation)
    then
    begin
      Pdevicemode(@LDevMode)^.union1.dmDisplayOrientation :=
        DWORD(LOrientation);
      LResult := ChangeDisplaySettingsEx(PChar(DeviceName), LDevMode,
        0, 0, nil);
      Result := LResult = DISP_CHANGE_SUCCESSFUL;
      if not Result then
        RaiseChangeDisplaySettingsError(LResult);
    end;
  end;
end;

function TMonitorDevice.SetResolution(const AResolution: string): Boolean;
var
  LWidth, LHeight: Integer;
begin
  Result := SplitResolution(AResolution, LWidth, LHeight);
  if Result then
    Result := SetResolution(LWidth, LHeight);
end;

function TMonitorDevice.SetResolution(AWidth, AHeight: Integer): Boolean;
var
  LDevMode: TDevMode;
  LResult: Integer;
  LNewWidth, LNewHeight: DWORD;
begin
  Result := False;

  ZeroMemory(@LDevMode, SizeOf(LDevMode));
  if EnumDisplaySettings(PChar(DeviceName), ENUM_CURRENT_SETTINGS, LDevMode)
  then
  begin
    if Pdevicemode(@LDevMode)^.union1.dmDisplayOrientation in [0, 2] then
    begin
      LNewWidth := AWidth;
      LNewHeight := AHeight;
    end
    else
    begin
      LNewWidth := AHeight;
      LNewHeight := AWidth;
    end;

    if (LDevMode.dmPelsHeight <> LNewHeight) or
      (LDevMode.dmPelsWidth <> LNewWidth) then
    begin
      LDevMode.dmPelsHeight := LNewHeight;
      LDevMode.dmPelsWidth := LNewWidth;

      LDevMode.dmFields := DM_PELSWIDTH or DM_PELSHEIGHT;
      LResult := ChangeDisplaySettingsEx(PChar(DeviceName), LDevMode,
        0, 0, nil);
      Result := LResult = DISP_CHANGE_SUCCESSFUL;
      if not Result then
        RaiseChangeDisplaySettingsError(LResult);
    end;
  end;
end;

{ TSettingList }

constructor TMonitorModeList.Create;
begin
  inherited Create(TSettingComparer.Create);
end;

{ TSettingComparer }

function TSettingComparer.Compare(const Left, Right: TMonitorModeItem): Integer;
begin
  Result := Left.Width - Right.Width;
  if Result = 0 then
    Result := Left.Height - Right.Height;
end;

{ TMonitorModeItem }

function TMonitorModeItem.Resolution: string;
begin
  Result := Format('%dx%d', [Width, Height])
end;

end.
