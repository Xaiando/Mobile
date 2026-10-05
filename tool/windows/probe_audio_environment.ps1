# Read-only environment diagnostic. No device, service or volume changes.
param([string]$OutputFile = 'windows-audio-environment-local-v4.json')
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace SommelierAudioDiagnostic {
  [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
  public class EnumeratorClass {}
  [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface Enumerator {
    [PreserveSig] int EnumAudioEndpoints(int flow, uint stateMask, out Collection devices);
    [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out Device device);
  }
  [ComImport, Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface Collection {
    [PreserveSig] int GetCount(out uint count);
  }
  [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  public interface Device {}
  public class Reading {
    public string Role; public string EnumerationHResult; public string CountHResult;
    public string DefaultEndpointHResult; public string ProbeError;
    public bool? HasDefaultRenderEndpoint; public uint? ActiveRenderEndpointCount;
  }
  public static class Probe {
    private static string Hex(int hr) { return "0x" + unchecked((uint)hr).ToString("X8"); }
    // E_NOTFOUND = HRESULT_FROM_WIN32(ERROR_NOT_FOUND), SDK mmdeviceapi.h.
    // Other failures do not establish whether an endpoint exists.
    public static bool? ClassifyDefaultEndpoint(int hr, bool returnedDevice) {
      if (hr == 0 && returnedDevice) return true;
      if (unchecked((uint)hr) == 0x80070490) return false;
      return null;
    }
    public static Reading Read(int role) {
      Enumerator enumerator = null; Collection devices = null; Device device = null;
      var result = new Reading {Role = role == 0 ? "console" : role == 1 ? "multimedia" : "communications"};
      try {
        enumerator = (Enumerator)new EnumeratorClass();
        int enumHr = enumerator.EnumAudioEndpoints(0, 1, out devices);
        result.EnumerationHResult = Hex(enumHr);
        if (enumHr >= 0 && devices != null) {
          uint count; int countHr = devices.GetCount(out count);
          result.CountHResult = Hex(countHr);
          if (countHr >= 0) result.ActiveRenderEndpointCount = count;
        }
        int hr = enumerator.GetDefaultAudioEndpoint(0, role, out device);
        result.DefaultEndpointHResult = Hex(hr);
        result.HasDefaultRenderEndpoint = ClassifyDefaultEndpoint(hr, device != null);
      } catch (Exception ex) {
        result.ProbeError = ex.GetType().Name + ": " + ex.Message;
      } finally {
        if (device != null) Marshal.ReleaseComObject(device);
        if (devices != null) Marshal.ReleaseComObject(devices);
        if (enumerator != null) Marshal.ReleaseComObject(enumerator);
      }
      return result;
    }
  }
}
'@
$readings = foreach ($role in @(0,1,2)) { [SommelierAudioDiagnostic.Probe]::Read($role) }
$services = foreach ($serviceName in @('Audiosrv','AudioEndpointBuilder')) {
  try {
    $service = Get-Service -Name $serviceName -ErrorAction Stop
    [ordered]@{name=$service.Name; status=$service.Status.ToString(); startType=$service.StartType.ToString(); probeError=$null}
  } catch {
    [ordered]@{name=$serviceName; status=$null; startType=$null; probeError=$_.Exception.Message}
  }
}
$result = [ordered]@{observedAt=[DateTime]::UtcNow.ToString('o'); readOnly=$true;
  noMicrophoneCapture=$true; noEndpointIdentifiersOrNames=$true; services=$services;
  renderEndpoints=@($readings); os=[Environment]::OSVersion.VersionString;
  scope='Environment metadata only. Probe errors are recorded; all integration assertions remain unchanged. Successful local results do not establish hosted runner availability.'}
$outputPath = if ([IO.Path]::IsPathRooted($OutputFile)) { $OutputFile } else { Join-Path $PSScriptRoot $OutputFile }
$result | ConvertTo-Json -Depth 6 | Tee-Object -FilePath $outputPath
