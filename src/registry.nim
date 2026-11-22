## Registry helpers for Brave DeBloater.
##
## Policies live under:
##   HKLM\SOFTWARE\Policies\BraveSoftware\Brave   (machine-wide, mandatory)
##   HKCU\SOFTWARE\Policies\BraveSoftware\Brave   (per-user, recommended)
##
## Brave reads BOTH locations. HKLM takes precedence for the same value.
## This module therefore keeps handles to both roots: reads consult HKLM first
## then HKCU, while writes go only to the chosen writable root (HKLM when
## elevated, HKCU otherwise). Revert deletes from both roots.

import std/options
import winim/lean
import winim/inc/shellapi

const
  PolicySubKey* = "SOFTWARE\\Policies\\BraveSoftware\\Brave"
  PolicyDisplayPath* = "SOFTWARE\\Policies\\BraveSoftware\\Brave"

type
  RootKind* = enum
    rkHklm   ## Machine-wide policy (requires administrator)
    rkHkcu   ## Per-user policy fallback

  PolicyStore* = object
    root*: RootKind     ## the root that writes go to
    hkey*: HKEY         ## handle for writes (same as hklmKey or hkcuKey)
    hklmKey*: HKEY      ## HKLM handle (read/write when elevated)
    hkcuKey*: HKEY      ## HKCU handle (read/write)
    canWrite*: bool
    elevated*: bool

# ---------------------------------------------------------------------------
# Low level helpers
# ---------------------------------------------------------------------------

proc regErrorText*(code: LONG): string =
  var buf = newWString(512)
  let n = FormatMessageW(
    FORMAT_MESSAGE_FROM_SYSTEM or FORMAT_MESSAGE_IGNORE_INSERTS,
    nil, DWORD(code), 0, buf, 512, nil)
  if n <= 0:
    return "error " & $code
  result = $buf
  if result.len > 0 and result[^1] == '\n':
    result = result[0 .. ^2]
  if result.len > 0 and result[^1] == '\r':
    result = result[0 .. ^2]

proc openKey(root: HKEY, path: string, access: REGSAM): HKEY =
  var h: HKEY
  let rc = RegOpenKeyExW(root, path, 0, access or KEY_WOW64_64KEY, addr h)
  if rc == ERROR_SUCCESS:
    return h
  return 0

proc createKey(root: HKEY, path: string, access: REGSAM): HKEY =
  var h: HKEY
  var disp: DWORD
  let rc = RegCreateKeyExW(root, path, 0, nil, 0,
    access or KEY_WOW64_64KEY, nil, addr h, addr disp)
  if rc == ERROR_SUCCESS:
    return h
  return 0

# ---------------------------------------------------------------------------
# Store selection
# ---------------------------------------------------------------------------

proc chooseStore*(): PolicyStore =
  ## Open both roots. Writes go to HKLM when elevated, otherwise HKCU.
  var store: PolicyStore
  store.elevated = IsUserAnAdmin() != 0

  # HKLM: writable when elevated, otherwise read-only so we can still detect
  # machine-wide policies set by an administrator.
  let hlmAccess: REGSAM = if store.elevated: KEY_READ or KEY_SET_VALUE else: KEY_READ
  var hlm = openKey(HKEY_LOCAL_MACHINE, PolicySubKey, hlmAccess)
  if hlm == 0 and store.elevated:
    hlm = createKey(HKEY_LOCAL_MACHINE, PolicySubKey, hlmAccess)
  store.hklmKey = hlm

  # HKCU: always read/write for the current user.
  var hcu = openKey(HKEY_CURRENT_USER, PolicySubKey, KEY_READ or KEY_SET_VALUE)
  if hcu == 0:
    hcu = createKey(HKEY_CURRENT_USER, PolicySubKey, KEY_READ or KEY_SET_VALUE)
  store.hkcuKey = hcu

  if store.elevated and hlm != 0:
    store.root = rkHklm
    store.hkey = hlm
  else:
    store.root = rkHkcu
    store.hkey = hcu
  store.canWrite = store.hkey != 0
  return store

proc close*(store: var PolicyStore) =
  if store.hklmKey != 0:
    discard RegCloseKey(store.hklmKey)
    store.hklmKey = 0
  if store.hkcuKey != 0:
    discard RegCloseKey(store.hkcuKey)
    store.hkcuKey = 0
  store.hkey = 0

proc rootName*(store: PolicyStore): string =
  case store.root
  of rkHklm: "HKLM"
  of rkHkcu: "HKCU"

proc rootDisplayName*(store: PolicyStore): string =
  "HKEY_" & (if store.root == rkHklm: "LOCAL_MACHINE" else: "CURRENT_USER") &
    "\\" & PolicyDisplayPath

proc writeDisplayName*(store: PolicyStore): string =
  "HKEY_" & (if store.root == rkHklm: "LOCAL_MACHINE" else: "CURRENT_USER") &
    "\\" & PolicyDisplayPath

proc rootShortName*(store: PolicyStore): string =
  store.rootName() & "\\" & PolicyDisplayPath

# ---------------------------------------------------------------------------
# Value access (reads consult both roots, HKLM first)
# ---------------------------------------------------------------------------

proc queryDword(hkey: HKEY, name: string): Option[DWORD] =
  if hkey == 0:
    return none(DWORD)
  var buf: array[4, byte]
  var cbbuf = DWORD(4)
  var vtype: DWORD = 0
  let rc = RegQueryValueExW(hkey, name, nil, addr vtype,
    cast[LPBYTE](addr buf[0]), addr cbbuf)
  if rc != ERROR_SUCCESS:
    return none(DWORD)
  if vtype != REG_DWORD or cbbuf < 4:
    return none(DWORD)
  var val: DWORD
  copyMem(addr val, addr buf[0], 4)
  return some(val)

proc queryString(hkey: HKEY, name: string): Option[string] =
  if hkey == 0:
    return none(string)
  var cbbuf = DWORD(0)
  var vtype: DWORD = 0
  var rc = RegQueryValueExW(hkey, name, nil, addr vtype, nil, addr cbbuf)
  if rc != ERROR_SUCCESS:
    return none(string)
  if (vtype != REG_SZ and vtype != REG_EXPAND_SZ) or cbbuf == 0:
    return none(string)
  # cbbuf counts bytes including the null terminator (2 bytes per WCHAR).
  var buf = newWString(int(cbbuf) div 2 + 1)
  rc = RegQueryValueExW(hkey, name, nil, addr vtype,
    cast[LPBYTE](&buf), addr cbbuf)
  if rc != ERROR_SUCCESS:
    return none(string)
  var s = $buf
  while s.len > 0 and s[^1] == '\0':
    s = s[0 .. ^2]
  result = some(s)

proc readDword*(store: PolicyStore, name: string): Option[DWORD] =
  let v = queryDword(store.hklmKey, name)
  if v.isSome:
    return v
  result = queryDword(store.hkcuKey, name)

proc readString*(store: PolicyStore, name: string): Option[string] =
  let v = queryString(store.hklmKey, name)
  if v.isSome:
    return v
  result = queryString(store.hkcuKey, name)

proc valueSource*(store: PolicyStore, name: string): string =
  ## Where the effective value lives: "HKLM", "HKCU" or "" when unset.
  if queryDword(store.hklmKey, name).isSome or queryString(store.hklmKey, name).isSome:
    return "HKLM"
  if queryDword(store.hkcuKey, name).isSome or queryString(store.hkcuKey, name).isSome:
    return "HKCU"
  return ""

# ---------------------------------------------------------------------------
# Mutations (write to the chosen root, revert from both)
# ---------------------------------------------------------------------------

proc writeDword*(store: PolicyStore, name: string, value: DWORD): bool =
  if store.hkey == 0:
    return false
  let rc = RegSetValueExW(store.hkey, name, 0, REG_DWORD,
    cast[ptr byte](addr value), DWORD(sizeof(DWORD)))
  result = rc == ERROR_SUCCESS

proc writeString*(store: PolicyStore, name: string, value: string): bool =
  if store.hkey == 0:
    return false
  var w = +$value
  let bytes = DWORD((w.len + 1) * 2)
  let rc = RegSetValueExW(store.hkey, name, 0, REG_SZ,
    cast[ptr byte](&w), bytes)
  result = rc == ERROR_SUCCESS

proc deleteValue*(store: PolicyStore, name: string): bool =
  ## Delete from both roots so a value written in a different elevation
  ## context is actually reverted. Missing values count as success.
  var ok = true
  for h in [store.hklmKey, store.hkcuKey]:
    if h != 0:
      let rc = RegDeleteValueW(h, name)
      if rc != ERROR_SUCCESS and rc != ERROR_FILE_NOT_FOUND:
        ok = false
  result = ok

proc ensureWritable*(store: var PolicyStore): bool =
  if store.hkey != 0:
    return true
  let h = createKey(HKEY_CURRENT_USER, PolicySubKey, KEY_READ or KEY_SET_VALUE)
  if h == 0:
    return false
  store.hkcuKey = h
  store.hkey = h
  store.root = rkHkcu
  store.canWrite = true
  result = true