## Brave DeBloater - a small Win32 GUI to toggle Brave browser feature /
## bloatware policies through the Windows registry, plus Secure DNS settings.

import std/options
import std/strutils
import winim/lean
import winim/inc/[commctrl, shellapi]
import registry, policy, dns

# ---------------------------------------------------------------------------
# Control IDs
# ---------------------------------------------------------------------------

const
  ID_LIST          = 1000
  ID_BTN_REFRESH   = 1001
  ID_BTN_CHECKALL  = 1002
  ID_BTN_CLEARALL  = 1003
  ID_BTN_REVERTALL = 1004
  ID_BTN_APPLY     = 1005
  ID_BTN_REVERT    = 1006

  ID_DNS_MODE      = 1010
  ID_DNS_PROVIDER  = 1011
  ID_DNS_TEMPLATE  = 1012
  ID_DNS_APPLY     = 1013
  ID_DNS_REVERT    = 1014

  ID_STATUS   = 1020
  ID_DNS_HINT = 1021

  IDC_STATIC = -1

  # Layout: derive everything from one margin so left/right padding match.
  Margin   = 12
  ClientW  = 900
  ClientH  = 520
  InnerW   = ClientW - 2 * Margin   # 876

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------

var
  gInstance: HINSTANCE
  gHwnd: HWND
  gStore: PolicyStore
  ghList: HWND
  ghStatus: HWND
  ghMode: HWND
  ghProvider: HWND
  ghTemplate: HWND
  ghHint: HWND
  ghFont: HFONT
  gLoaded = false

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

proc setFont(h: HWND) =
  if ghFont != 0 and h != 0:
    discard SendMessageW(h, WM_SETFONT, cast[WPARAM](ghFont), 1)

proc createControl(class: string, text: string, style: DWORD,
    x, y, w, h: int, id: int, parent: HWND): HWND =
  result = CreateWindowExW(0, class, text, WS_CHILD or WS_VISIBLE or style,
    int32(x), int32(y), int32(w), int32(h), parent, cast[HMENU](id), gInstance, nil)

proc setText(h: HWND, text: string) =
  if h != 0:
    discard SetWindowTextW(h, text)

proc getText(h: HWND): string =
  if h == 0:
    return ""
  let n = GetWindowTextLengthW(h)
  if n <= 0:
    return ""
  var buf = newWString(n + 1)
  let got = GetWindowTextW(h, buf, n + 2)
  if got <= 0:
    return ""
  result = $buf

proc comboReset(h: HWND) =
  if h != 0:
    discard SendMessageW(h, CB_RESETCONTENT, 0, 0)

proc comboAdd(h: HWND, s: string) =
  if h != 0:
    var w = +$s
    discard SendMessageW(h, CB_ADDSTRING, 0, cast[LPARAM](&w))

proc comboSetSel(h: HWND, idx: int) =
  if h != 0:
    discard SendMessageW(h, CB_SETCURSEL, cast[WPARAM](idx), 0)

proc comboCurSel(h: HWND): int =
  if h == 0:
    return -1
  result = int SendMessageW(h, CB_GETCURSEL, 0, 0)

proc messageInfo(text: string, caption = "Brave DeBloater") =
  discard MessageBoxW(gHwnd, text, caption, MB_OK or MB_ICONINFORMATION)

proc messageError(text: string, caption = "Brave DeBloater") =
  discard MessageBoxW(gHwnd, text, caption, MB_OK or MB_ICONERROR)

proc confirm(text: string, caption = "Brave DeBloater"): bool =
  result = MessageBoxW(gHwnd, text, caption, MB_YESNO or MB_ICONQUESTION) == IDYES

# ---------------------------------------------------------------------------
# ListView setup
# ---------------------------------------------------------------------------

proc addColumn(lv: HWND, index: int, title: string, width: int) =
  var col: LVCOLUMNW
  col.mask = LVCF_FMT or LVCF_WIDTH or LVCF_TEXT
  col.fmt = int32(LVCFMT_LEFT)
  col.cx = int32(width)
  col.pszText = title
  discard ListView_InsertColumn(lv, int32(index), addr col)

proc addGroup(lv: HWND, index: int, header: string) =
  var grp: LVGROUP
  grp.cbSize = int32(sizeof(LVGROUP))
  grp.mask = LVGF_HEADER or LVGF_GROUPID
  grp.pszHeader = header
  grp.iGroupId = int32(index)
  discard ListView_InsertGroup(lv, int32(index), addr grp)

proc addItem(lv: HWND, index: int, text: string, groupId: int): int32 =
  var w = +$text
  var item: LVITEMW
  item.mask = LVIF_TEXT or LVIF_GROUPID
  item.iItem = int32(index)
  item.iSubItem = 0
  item.pszText = &w
  item.iGroupId = int32(groupId)
  result = ListView_InsertItem(lv, addr item)

proc setSubItem(lv: HWND, index: int, sub: int, text: string) =
  ListView_SetItemText(lv, int32(index), int32(sub), text)

proc setCheck(lv: HWND, index: int, checked: bool) =
  var lvi = LVITEMW(stateMask: LVIS_STATEIMAGEMASK,
    state: UINT(INDEXTOSTATEIMAGEMASK(if checked: 2 else: 1)))
  discard SendMessageW(lv, LVM_SETITEMSTATE, cast[WPARAM](index), cast[LPARAM](addr lvi))

proc isChecked(lv: HWND, index: int): bool =
  let st = int(SendMessageW(lv, LVM_GETITEMSTATE, cast[WPARAM](index),
    cast[LPARAM](LVIS_STATEIMAGEMASK)))
  result = ((st shr 12) - 1) != 0

proc fillTooltip(pszText: LPWSTR, cchTextMax: int32, s: string) =
  ## Copy `s` into a LVN_GETINFOTIP wide-char buffer, NUL terminated.
  if pszText == nil or cchTextMax <= 0:
    return
  var w = +$s
  let n = min(w.len, cchTextMax - 1)
  if n > 0:
    copyMem(cast[ptr byte](pszText), cast[ptr byte](&w), n * 2)
  let dest = cast[ptr UncheckedArray[WCHAR]](pszText)
  dest[n] = WCHAR(0)

# ---------------------------------------------------------------------------
# Data loading / refresh
# ---------------------------------------------------------------------------

proc updateStatusLabel() =
  var active = 0
  for def in Policies:
    if gStore.isApplied(def):
      inc active
  var txt = "Writes: " & gStore.rootShortName() & "   |   Reads: HKLM + HKCU"
  if gStore.root == rkHklm:
    txt &= "   |   Administrator (machine-wide)"
  else:
    txt &= "   |   Run as admin to write HKLM"
  txt &= "   |   " & $active & "/" & $(Policies.len) & " active"
  setText(ghStatus, txt)

proc populateList() =
  ListView_DeleteAllItems(ghList)
  var groupId = 0
  var lastGroup = ""
  var index = 0
  for def in Policies:
    if def.group != lastGroup:
      addGroup(ghList, groupId, def.group)
      lastGroup = def.group
      inc groupId
    discard addItem(ghList, index, def.label, groupId - 1)
    setSubItem(ghList, index, 1, def.group)
    setSubItem(ghList, index, 2, def.valueName)
    setSubItem(ghList, index, 3, statusOf(gStore, def))
    setCheck(ghList, index, gStore.isApplied(def))
    inc index

proc loadDnsControls() =
  let st = gStore.readDnsState()
  comboReset(ghMode)
  comboAdd(ghMode, "Off")
  comboAdd(ghMode, "Automatic (use current service)")
  comboAdd(ghMode, "Secure (DNS-over-HTTPS)")
  case st.mode
  of "off": comboSetSel(ghMode, 0)
  of "secure": comboSetSel(ghMode, 2)
  else: comboSetSel(ghMode, 1)

  comboReset(ghProvider)
  var idx = 0
  var matched = 0
  for p in Providers:
    comboAdd(ghProvider, p.name)
    if p.templateUrl.len > 0 and p.templateUrl == st.templateUrl:
      matched = idx
    inc idx
  comboSetSel(ghProvider, if st.hasTemplate and matched > 0: matched else: 0)

  if st.hasTemplate:
    setText(ghTemplate, st.templateUrl)
  else:
    setText(ghTemplate, Providers[0].templateUrl)

  let cur = comboCurSel(ghProvider)
  if cur >= 0 and cur < Providers.len:
    setText(ghHint, Providers[cur].note)

proc refreshAll() =
  populateList()
  loadDnsControls()
  updateStatusLabel()

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

proc applyChecked() =
  var applied = 0
  var failed = 0
  for i, def in Policies:
    if isChecked(ghList, i):
      if gStore.apply(def): inc applied else: inc failed
  refreshAll()
  if failed > 0:
    messageError("Applied " & $applied & " policies, but " & $failed &
      " failed. Try running as administrator.")
  else:
    messageInfo("Applied " & $applied & " policies.")

proc revertChecked() =
  var reverted = 0
  var failed = 0
  for i, def in Policies:
    if isChecked(ghList, i):
      if gStore.revert(def): inc reverted else: inc failed
  refreshAll()
  if failed > 0:
    messageError("Reverted " & $reverted & " policies, but " & $failed & " failed.")
  else:
    messageInfo("Reverted " & $reverted & " policies.")

proc revertAll() =
  if not confirm("Remove ALL Brave policies managed by this tool?"):
    return
  var reverted = 0
  for def in Policies:
    if gStore.revert(def): inc reverted
  discard gStore.revertDns()
  refreshAll()
  messageInfo("Reverted " & $reverted & " policies and cleared Secure DNS settings.")

proc checkAll() =
  for i in 0 ..< Policies.len:
    setCheck(ghList, i, true)

proc clearAll() =
  for i in 0 ..< Policies.len:
    setCheck(ghList, i, false)

proc applyDns() =
  let modeIdx = comboCurSel(ghMode)
  let mode = case modeIdx
    of 0: "off"
    of 2: "secure"
    else: "automatic"
  var tpl = ""
  if mode == "secure":
    tpl = getText(ghTemplate).strip()
    if tpl.len == 0:
      messageError("Secure DNS needs a template URL. Pick a provider or enter one.")
      return
  if gStore.applyDns(mode, tpl):
    loadDnsControls()
    updateStatusLabel()
    messageInfo("Secure DNS settings applied.")
  else:
    messageError("Could not write DNS policies. Try running as administrator.")

proc revertDns() =
  if gStore.revertDns():
    loadDnsControls()
    messageInfo("Secure DNS settings reverted.")
  else:
    messageError("Could not revert DNS policies.")

# ---------------------------------------------------------------------------
# Window procedure
# ---------------------------------------------------------------------------

proc WndProc(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
  case msg
  of WM_COMMAND:
    let id = int(uint16(wParam and 0xFFFF))
    let code = int(uint16((wParam shr 16) and 0xFFFF))
    case id
    of ID_BTN_APPLY: applyChecked()
    of ID_BTN_REVERT: revertChecked()
    of ID_BTN_REVERTALL: revertAll()
    of ID_BTN_REFRESH: refreshAll()
    of ID_BTN_CHECKALL: checkAll()
    of ID_BTN_CLEARALL: clearAll()
    of ID_DNS_APPLY: applyDns()
    of ID_DNS_REVERT: revertDns()
    of ID_DNS_PROVIDER:
      if code == CBN_SELCHANGE:
        let idx = comboCurSel(ghProvider)
        if idx >= 0 and idx < Providers.len:
          if Providers[idx].templateUrl.len > 0:
            setText(ghTemplate, Providers[idx].templateUrl)
          setText(ghHint, Providers[idx].note)
    else: discard
    return 0

  of WM_NOTIFY:
    let nm = cast[LPNMHDR](lParam)
    if nm != nil and nm.idFrom == ID_LIST and
        int32(nm.code) == LVN_GETINFOTIPW:
      let tip = cast[LPNMLVGETINFOTIPW](nm)
      let i = tip.iItem
      if i >= 0 and i < Policies.len:
        fillTooltip(tip.pszText, tip.cchTextMax, Policies[i].description)
    return 0

  of WM_CTLCOLORSTATIC:
    let dc = cast[HDC](wParam)
    SetBkMode(dc, TRANSPARENT)
    discard SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT))
    return cast[LRESULT](GetSysColorBrush(COLOR_BTNFACE))

  of WM_SETFOCUS:
    if ghList != 0:
      discard SetFocus(ghList)
    return 0

  of WM_DESTROY:
    PostQuitMessage(0)
    return 0

  else:
    return DefWindowProcW(hwnd, msg, wParam, lParam)

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------

proc buildUi(hwnd: HWND) =
  gHwnd = hwnd
  ghFont = cast[HFONT](GetStockObject(DEFAULT_GUI_FONT))

  # --- status label ------------------------------------------------------
  ghStatus = createControl("STATIC", "", SS_LEFT,
    Margin, 8, InnerW, 18, ID_STATUS, hwnd)

  # --- list view ---------------------------------------------------------
  var icc: TINITCOMMONCONTROLSEX
  icc.dwSize = DWORD(sizeof(TINITCOMMONCONTROLSEX))
  icc.dwICC = ICC_LISTVIEW_CLASSES or ICC_STANDARD_CLASSES
  discard InitCommonControlsEx(addr icc)

  ghList = CreateWindowExW(WS_EX_CLIENTEDGE, "SysListView32", "",
    WS_CHILD or WS_VISIBLE or LVS_REPORT or LVS_SHOWSELALWAYS,
    Margin, 32, InnerW, 300, hwnd, cast[HMENU](ID_LIST), gInstance, nil)

  ListView_SetExtendedListViewStyle(ghList,
    LVS_EX_CHECKBOXES or LVS_EX_FULLROWSELECT or LVS_EX_GRIDLINES or
    LVS_EX_DOUBLEBUFFER or LVS_EX_INFOTIP)
  ListView_EnableGroupView(ghList, 1)
  # Sum 815 fits within InnerW minus the client-edge border and the vertical
  # scrollbar, so the grid fills the view without a horizontal scrollbar.
  addColumn(ghList, 0, "Policy", 285)
  addColumn(ghList, 1, "Group", 145)
  addColumn(ghList, 2, "Registry value", 238)
  addColumn(ghList, 3, "State", 147)

  # --- buttons -----------------------------------------------------------
  discard createControl("BUTTON", "Refresh", BS_PUSHBUTTON,
    Margin, 340, 90, 28, ID_BTN_REFRESH, hwnd)
  discard createControl("BUTTON", "Check all", BS_PUSHBUTTON,
    110, 340, 90, 28, ID_BTN_CHECKALL, hwnd)
  discard createControl("BUTTON", "Clear all", BS_PUSHBUTTON,
    208, 340, 90, 28, ID_BTN_CLEARALL, hwnd)
  discard createControl("BUTTON", "Revert all", BS_PUSHBUTTON,
    306, 340, 90, 28, ID_BTN_REVERTALL, hwnd)

  discard createControl("BUTTON", "Apply checked", BS_DEFPUSHBUTTON,
    ClientW - Margin - 268, 340, 130, 28, ID_BTN_APPLY, hwnd)
  discard createControl("BUTTON", "Revert checked", BS_PUSHBUTTON,
    ClientW - Margin - 130, 340, 130, 28, ID_BTN_REVERT, hwnd)

  # --- DNS group box -----------------------------------------------------
  # Inner content is inset InnerPad px from the group box on BOTH sides:
  #   group box: x = Margin .. Margin + InnerW  (12 .. 888)
  #   content:   x = 24 .. 876                 (852 px wide)
  const InnerPad = 12
  let gx = Margin + InnerPad            # 24
  let gw = InnerW - 2 * InnerPad        # 852

  discard createControl("BUTTON", "Secure DNS (DNS-over-HTTPS)",
    BS_GROUPBOX or WS_GROUP, Margin, 378, InnerW, 128, IDC_STATIC, hwnd)

  # Row 1: two equal columns spanning the full inner width (gap between them).
  let colW = (gw - 24) div 2            # 414
  let col2 = gx + colW + 24             # 462
  discard createControl("STATIC", "Mode:", SS_LEFT, gx, 405, 80, 18, IDC_STATIC, hwnd)
  ghMode = createControl("COMBOBOX", "", CBS_DROPDOWNLIST or WS_TABSTOP,
    gx + 84, 402, colW - 84, 240, ID_DNS_MODE, hwnd)

  discard createControl("STATIC", "Provider:", SS_LEFT, col2, 405, 75, 18, IDC_STATIC, hwnd)
  ghProvider = createControl("COMBOBOX", "", CBS_DROPDOWNLIST or WS_TABSTOP,
    col2 + 84, 402, colW - 84, 240, ID_DNS_PROVIDER, hwnd)

  # Row 2: label + template edit + buttons, right-aligned to the same edge.
  discard createControl("STATIC", "Template URL:", SS_LEFT, gx, 435, 110, 18, IDC_STATIC, hwnd)
  ghTemplate = createControl("EDIT", "", WS_BORDER or WS_TABSTOP or ES_AUTOHSCROLL,
    gx + 118, 432, gw - 118 - 288 - 8, 24, ID_DNS_TEMPLATE, hwnd)

  discard createControl("BUTTON", "Apply DNS", BS_PUSHBUTTON,
    gx + gw - 288, 431, 130, 26, ID_DNS_APPLY, hwnd)
  discard createControl("BUTTON", "Revert DNS", BS_PUSHBUTTON,
    gx + gw - 148, 431, 148, 26, ID_DNS_REVERT, hwnd)

  ghHint = createControl("STATIC", "", SS_LEFT, gx, 464, gw, 28, ID_DNS_HINT, hwnd)

  # --- apply the GUI font to everything ----------------------------------
  var h = GetWindow(hwnd, GW_CHILD)
  while h != 0:
    setFont(h)
    h = GetWindow(h, GW_HWNDNEXT)

  gLoaded = true
  refreshAll()

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

proc main() =
  gInstance = GetModuleHandleW(nil)
  gStore = chooseStore()

  var wc: WNDCLASSEXW
  wc.cbSize = int32(sizeof(WNDCLASSEXW))
  wc.style = CS_HREDRAW or CS_VREDRAW
  wc.lpfnWndProc = WndProc
  wc.hInstance = gInstance
  wc.hIcon = LoadIconW(gInstance, MAKEINTRESOURCE(1))
  wc.hCursor = LoadCursorW(0, IDC_ARROW)
  wc.hbrBackground = cast[HBRUSH](COLOR_BTNFACE + 1)
  wc.lpszClassName = "BraveDeBloaterWnd"

  if RegisterClassExW(addr wc) == 0:
    messageError("Failed to register window class.")
    return

  # Fixed-size window (no resize border). Size it so the client area is
  # exactly ClientW x ClientH, which keeps left/right padding symmetric.
  let style = DWORD(WS_OVERLAPPED or WS_CAPTION or WS_SYSMENU or WS_MINIMIZEBOX)
  var wr = RECT(left: 0, top: 0, right: int32(ClientW), bottom: int32(ClientH))
  discard AdjustWindowRectEx(addr wr, style, 0, 0)
  gHwnd = CreateWindowExW(0, "BraveDeBloaterWnd", "Brave DeBloater",
    style, CW_USEDEFAULT, CW_USEDEFAULT,
    wr.right - wr.left, wr.bottom - wr.top, 0, 0, gInstance, nil)

  if gHwnd == 0:
    messageError("Failed to create window.")
    gStore.close()
    return

  buildUi(gHwnd)

  discard ShowWindow(gHwnd, SW_SHOW)
  discard UpdateWindow(gHwnd)

  var msg: MSG
  while GetMessageW(addr msg, 0, 0, 0) > 0:
    discard TranslateMessage(addr msg)
    discard DispatchMessageW(addr msg)

  gStore.close()

when isMainModule:
  main()