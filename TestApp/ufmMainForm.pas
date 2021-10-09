unit ufmMainForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.Variants, Winapi.Messages, FMX.Platform.Win,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.StdCtrls, FMX.Controls.Presentation, FMX.ListBox, Winapi.Windows,
  FMX.Layouts, uMultiDisplay;

type
  TfrmDeviceSettings = class(TForm)
    btnOK: TButton;
    btnCancel: TButton;
    cbbMonitor: TComboBox;
    cbbResolution: TComboBox;
    cbbOrientation: TComboBox;
    chkMonitor: TCheckBox;
    chkResolution: TCheckBox;
    chkOrientation: TCheckBox;
    pnlContent: TPanel;
    pnlMain: TPanel;
    lytMain: TLayout;
    lblCaption: TLabel;
    procedure btnOKClick(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure cbbMonitorChange(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure cbbResolutionChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure cbbOrientationChange(Sender: TObject);
    procedure chkMonitorChange(Sender: TObject);
  private
    FMultiDisplay: TMultiDisplay;
  private
    procedure UpdateControls;
    procedure UpdateModeListContol;
    procedure UpdateControlsEnabled;
    procedure ApplySettings;
    procedure OnUpdateMonitorList(ASender: TObject);
  public
    { Public declarations }
  end;

var
  frmDeviceSettings: TfrmDeviceSettings;

implementation

resourcestring
  RsNeedRestartWarning =
    'Для применения настроек, необходимо перезапустить приложение' + sLineBreak
    + 'Продолжить?';
  RsWarning = 'Предупреждение';

{$R *.fmx}

procedure TfrmDeviceSettings.ApplySettings;
var
  LMonitor: TMonitorDevice;
  LResolution: string;
  LOrientation: TMonitorOrientation;
begin
  if (not chkMonitor.IsChecked) and (cbbMonitor.ItemIndex < 0) then
    Exit;

  LMonitor := TMonitorDevice(cbbMonitor.Items.Objects[cbbMonitor.ItemIndex]);
  LResolution := '';
  LOrientation := moUnknown;

  if chkOrientation.IsChecked and (cbbOrientation.ItemIndex >= 0) then
    LOrientation := TMonitorOrientation(cbbOrientation.ItemIndex);

  if chkResolution.IsChecked and (cbbResolution.ItemIndex >= 0) then
    LResolution := cbbResolution.Items[cbbResolution.ItemIndex];

  LMonitor.SetMode(LResolution, LOrientation);
end;

procedure TfrmDeviceSettings.btnCancelClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmDeviceSettings.btnOKClick(Sender: TObject);
begin
  ApplySettings;
end;

procedure TfrmDeviceSettings.cbbMonitorChange(Sender: TObject);
begin
  chkMonitor.IsChecked := cbbMonitor.ItemIndex >= 0;
  if cbbMonitor.ItemIndex < 0 then
    Exit;

  UpdateModeListContol;
  UpdateControlsEnabled;
end;

procedure TfrmDeviceSettings.cbbResolutionChange(Sender: TObject);
begin
  chkResolution.IsChecked := cbbResolution.ItemIndex >= 0;
end;

procedure TfrmDeviceSettings.cbbOrientationChange(Sender: TObject);
begin
  chkOrientation.IsChecked := cbbOrientation.ItemIndex >= 0;
end;

procedure TfrmDeviceSettings.chkMonitorChange(Sender: TObject);
begin
  UpdateControlsEnabled;
end;

procedure TfrmDeviceSettings.FormCreate(Sender: TObject);
var
  I: TMonitorOrientation;
begin
  FMultiDisplay := TMultiDisplay.Create;
  FMultiDisplay.OnUpdateMonitorList := OnUpdateMonitorList;

  cbbOrientation.Clear;
  for I := Low(TMonitorOrientation) to High(TMonitorOrientation) do
    cbbOrientation.Items.Add(MONITOR_ORIENTATIONS[I]);
end;

procedure TfrmDeviceSettings.FormDestroy(Sender: TObject);
begin
  cbbResolution.Clear;
  cbbMonitor.Clear;

  FMultiDisplay.Free;
end;

procedure TfrmDeviceSettings.FormShow(Sender: TObject);
begin
  UpdateControls;
  UpdateControlsEnabled;
end;

procedure TfrmDeviceSettings.OnUpdateMonitorList(ASender: TObject);
begin
  UpdateControls;
end;

procedure TfrmDeviceSettings.UpdateControls;
var
  I: Integer;
begin
  chkMonitor.IsChecked := False;
  chkResolution.IsChecked := False;
  chkOrientation.IsChecked := False;
  cbbResolution.Clear;
  cbbMonitor.Clear;
  cbbOrientation.ItemIndex := -1;

  for I := 0 to FMultiDisplay.MonitorList.Count - 1 do
    cbbMonitor.Items.AddObject(FMultiDisplay.MonitorList[I].FriendlyName,
      FMultiDisplay.MonitorList[I]);
end;

procedure TfrmDeviceSettings.UpdateControlsEnabled;
var
  LMonitorSelected: Boolean;
begin
  LMonitorSelected := chkMonitor.IsChecked and (cbbMonitor.ItemIndex >= 0);

  chkResolution.Enabled := LMonitorSelected;
  cbbResolution.Enabled := LMonitorSelected;
  chkOrientation.Enabled := LMonitorSelected;
  cbbOrientation.Enabled := LMonitorSelected;
end;

procedure TfrmDeviceSettings.UpdateModeListContol;
var
  I: Integer;
  LModes: TMonitorModeList;
  LMonitor: TMonitorDevice;
begin
  chkResolution.IsChecked := False;
  if (cbbMonitor.ItemIndex < 0) or
    (not Assigned(cbbMonitor.Items.Objects[cbbMonitor.ItemIndex])) then
    Exit;

  LMonitor := TMonitorDevice(cbbMonitor.Items.Objects[cbbMonitor.ItemIndex]);
  LModes := LMonitor.Modes;

  cbbResolution.Clear;
  for I := Pred(LModes.Count) downto 0 do
    cbbResolution.Items.Add(LModes[I].Resolution);
end;

end.
