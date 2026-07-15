# Endpoint Folder

This folder is the deployable Windows endpoint package.

## Purpose

Install and remove the endpoint components needed to send telemetry into the ISHA-X EDR lab:

| Component | Purpose |
|---|---|
| Sysmon | Generates process, registry, file, and network telemetry. |
| Wazuh Agent | Ships Windows Event Log data to Wazuh Manager. |
| AMSI watcher | Collects AMSI ETW script scan events into the `ISHAX-AMSI` channel. |

## Files

| File | Purpose |
|---|---|
| `SETUP ENDPOINT.bat` | Administrator launcher for setup. Prompts for Wazuh Manager IP/DNS. |
| `UNINSTALL ENDPOINT.bat` | Administrator launcher for cleanup. |
| `endpoint_setup.ps1` | Main endpoint install logic. |
| `uninstall_endpoint.ps1` | Removes Sysmon, Wazuh Agent, AMSI service, and staged runtime files. |
| `sysmon_config.xml` | Sysmon rules required by the project. |
| `amsi_watcher.exe` | AMSI ETW watcher service binary. |
| `amsi_sanity_check.ps1` | Optional manual AMSI verification helper. |

## Runtime Install Location

The installer stages runtime files into:

```text
%ProgramFiles(x86)%\ISHA-X
```

This keeps Windows services from depending on a temporary extraction path.

## Moved Out

Atomic Red Team offline assets and the old automated runner were moved to:

```text
..\recovery\endpoint_extras\
```

They are useful for lab testing but are not required on every endpoint.

