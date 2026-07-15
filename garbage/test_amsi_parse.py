import json

raw_json = '''{
  "timestamp": "2026-07-11T20:03:38.330+0000",
  "data": {
    "win": {
      "eventdata": {
        "data": "{\\"pid\\":8824,\\"process_guid\\":\\"fc4c96d3-a194-6a52-ec00-000000001600\\",\\"content_name\\":\\"PowerShell_C:\\\\\\\\Windows\\\\\\\\System32\\\\\\\\WindowsPowerShell\\\\\\\\v1.0\\\\\\\\powershell.exe_10.0.26100.5074\\",\\"scan_result\\":1,\\"content_hex\\":\\"660075006e00\\",\\"host_id\\":\\"WIN11\\"}"
      }
    }
  }
}'''

ev = json.loads(raw_json)
edata = ev.get('data', {}).get('win', {}).get('eventdata', {})

def ci_get(d, *keys, default=None):
    if not isinstance(d, dict): return default
    for k in keys:
        for _k, _v in d.items():
            if k.lower() == _k.lower():
                return _v
    return default

amsi_raw = ci_get(edata, 'param1', 'data', default='')
print('RAW:', amsi_raw)
try:
    amsi_obj = json.loads(amsi_raw)
    print('OBJ:', amsi_obj)
    print('content_name:', ci_get(amsi_obj, 'content_name', 'contentName'))
except Exception as e:
    print('Error:', e)
