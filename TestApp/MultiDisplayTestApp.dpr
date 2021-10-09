program MultiDisplayTestApp;

uses
  System.StartUpCopy,
  FMX.Forms,
  ufmMainForm in 'ufmMainForm.pas' {frmDeviceSettings},
  uMultiDisplay in '..\uMultiDisplay.pas';

{$R *.res}

begin
{$IFDEF DEBUG}
  // ��� ����������� ������ ������, ���� ��� ����
  ReportMemoryLeaksOnShutdown := True;
{$ENDIF}
  Application.Initialize;
  Application.CreateForm(TfrmDeviceSettings, frmDeviceSettings);
  Application.Run;
end.
