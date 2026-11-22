## Brave policy definitions for Brave DeBloater.
##
## Each row in the UI corresponds to one policy. The checkbox means
## "apply this policy" (i.e. enforce the debloat / hardening action).
## Unchecking it deletes the value so Brave falls back to its default and the
## user regains control.

import std/options
import winim/lean
import registry

type
  PolicyKind* = enum
    pkBoolDisable  ## value 1 = feature disabled (e.g. BraveRewardsDisabled)
    pkBoolEnable   ## value 0 = feature disabled (e.g. BraveAIChatEnabled)
    pkBoolForceOn  ## value 1 = protection enabled
    pkInt          ## specific integer value (Shields enums)

  PolicyDef* = object
    label*: string        ## text shown in the list (describes the action)
    valueName*: string    ## registry value name
    kind*: PolicyKind
    applyValue*: DWORD    ## value written when the row is checked
    group*: string        ## ListView group header
    description*: string  ## short explanation shown in the status bar

const
  GroupFeatures* = "Brave features (disable)"
  GroupTelemetry* = "Telemetry & tracking (disable)"
  GroupPrivacy* = "Privacy hardening (enable)"
  GroupShields* = "Shields defaults (enforce)"

# ---------------------------------------------------------------------------
# Policy table
# ---------------------------------------------------------------------------

const Policies*: seq[PolicyDef] = @[
  # --- Brave features -------------------------------------------------------
  PolicyDef(label: "Disable Brave Rewards", valueName: "BraveRewardsDisabled",
    kind: pkBoolDisable, applyValue: 1, group: GroupFeatures,
    description: "Turn off Brave Rewards and its ads/contributions UI."),
  PolicyDef(label: "Disable Brave Wallet", valueName: "BraveWalletDisabled",
    kind: pkBoolDisable, applyValue: 1, group: GroupFeatures,
    description: "Hide the built-in crypto wallet."),
  PolicyDef(label: "Disable Brave News", valueName: "BraveNewsDisabled",
    kind: pkBoolDisable, applyValue: 1, group: GroupFeatures,
    description: "Remove the Brave News feed from the new tab page."),
  PolicyDef(label: "Disable Brave VPN", valueName: "BraveVPNDisabled",
    kind: pkBoolDisable, applyValue: 1, group: GroupFeatures,
    description: "Hide the Brave VPN (paid) integration."),
  PolicyDef(label: "Disable Brave Talk", valueName: "BraveTalkDisabled",
    kind: pkBoolDisable, applyValue: 1, group: GroupFeatures,
    description: "Hide Brave Talk video calling."),
  PolicyDef(label: "Disable AI Chat", valueName: "BraveAIChatEnabled",
    kind: pkBoolEnable, applyValue: 0, group: GroupFeatures,
    description: "Turn off the built-in AI assistant (Leo)."),
  PolicyDef(label: "Disable Playlist", valueName: "BravePlaylistEnabled",
    kind: pkBoolEnable, applyValue: 0, group: GroupFeatures,
    description: "Turn off Brave Playlist."),
  PolicyDef(label: "Disable Speedreader", valueName: "BraveSpeedreaderEnabled",
    kind: pkBoolEnable, applyValue: 0, group: GroupFeatures,
    description: "Turn off the Speedreader clutter remover."),
  PolicyDef(label: "Disable Wayback Machine", valueName: "BraveWaybackMachineEnabled",
    kind: pkBoolEnable, applyValue: 0, group: GroupFeatures,
    description: "Turn off Wayback Machine integration."),
  PolicyDef(label: "Disable IPFS", valueName: "IPFSEnabled",
    kind: pkBoolEnable, applyValue: 0, group: GroupFeatures,
    description: "Turn off the (deprecated) IPFS feature."),
  PolicyDef(label: "Disable Email Aliases", valueName: "EmailAliasesEnabled",
    kind: pkBoolEnable, applyValue: 0, group: GroupFeatures,
    description: "Hide the Email Aliases feature."),
  PolicyDef(label: "Disable Tor windows", valueName: "TorDisabled",
    kind: pkBoolDisable, applyValue: 1, group: GroupFeatures,
    description: "Turn off New Private Window with Tor."),
  PolicyDef(label: "Disable Local AI", valueName: "BraveLocalAIEnabled",
    kind: pkBoolEnable, applyValue: 0, group: GroupFeatures,
    description: "Turn off on-device AI features and components."),
  PolicyDef(label: "Disable Password Manager", valueName: "PasswordManagerEnabled",
    kind: pkBoolEnable, applyValue: 0, group: GroupFeatures,
    description: "Stop offering to save new passwords. Previously saved passwords still work."),

  # --- Telemetry ------------------------------------------------------------
  PolicyDef(label: "Disable stats ping", valueName: "BraveStatsPingEnabled",
    kind: pkBoolEnable, applyValue: 0, group: GroupTelemetry,
    description: "Turn off the anonymous usage ping sent to Brave."),
  PolicyDef(label: "Disable P3A", valueName: "BraveP3AEnabled",
    kind: pkBoolEnable, applyValue: 0, group: GroupTelemetry,
    description: "Turn off Privacy-Preserving Product Analytics."),
  PolicyDef(label: "Disable Web Discovery", valueName: "BraveWebDiscoveryEnabled",
    kind: pkBoolEnable, applyValue: 0, group: GroupTelemetry,
    description: "Turn off contributing to Brave's search index."),

  # --- Privacy hardening ----------------------------------------------------
  PolicyDef(label: "Enable De-AMP", valueName: "BraveDeAmpEnabled",
    kind: pkBoolForceOn, applyValue: 1, group: GroupPrivacy,
    description: "Bypass Google-hosted AMP pages."),
  PolicyDef(label: "Enable Debouncing", valueName: "BraveDebouncingEnabled",
    kind: pkBoolForceOn, applyValue: 1, group: GroupPrivacy,
    description: "Protect against bounce tracking."),
  PolicyDef(label: "Enable Reduce language", valueName: "BraveReduceLanguageEnabled",
    kind: pkBoolForceOn, applyValue: 1, group: GroupPrivacy,
    description: "Block fingerprinting based on language preferences."),
  PolicyDef(label: "Enable Global Privacy Control",
    valueName: "BraveGlobalPrivacyControlEnabled",
    kind: pkBoolForceOn, applyValue: 1, group: GroupPrivacy,
    description: "Send the Sec-GPC opt-out-of-selling signal."),
  PolicyDef(label: "Enable tracking query filter",
    valueName: "BraveTrackingQueryParametersFilteringEnabled",
    kind: pkBoolForceOn, applyValue: 1, group: GroupPrivacy,
    description: "Strip known tracking parameters from URLs."),

  # --- Shields defaults -----------------------------------------------------
  PolicyDef(label: "Enforce: block ads", valueName: "DefaultBraveAdblockSetting",
    kind: pkInt, applyValue: 2, group: GroupShields,
    description: "Force Shields ad blocking on (value 2 = BlockAds)."),
  PolicyDef(label: "Enforce: fingerprinting protection",
    valueName: "DefaultBraveFingerprintingV2Setting",
    kind: pkInt, applyValue: 3, group: GroupShields,
    description: "Force standard fingerprinting protection (value 3)."),
  PolicyDef(label: "Enforce: require HTTPS",
    valueName: "DefaultBraveHttpsUpgradeSetting",
    kind: pkInt, applyValue: 2, group: GroupShields,
    description: "Force HTTPS-First strict mode (value 2)."),
  PolicyDef(label: "Enforce: strict referrers",
    valueName: "DefaultBraveReferrersSetting",
    kind: pkInt, applyValue: 2, group: GroupShields,
    description: "Cap referrers to strict-origin-when-cross-origin (value 2)."),
  PolicyDef(label: "Enforce: forget first-party storage",
    valueName: "DefaultBraveRemember1PStorageSetting",
    kind: pkInt, applyValue: 2, group: GroupShields,
    description: "Clear first-party storage on exit (value 2)."),
]

# ---------------------------------------------------------------------------
# State queries
# ---------------------------------------------------------------------------

proc currentValue*(store: PolicyStore, def: PolicyDef): Option[DWORD] =
  store.readDword(def.valueName)

proc isApplied*(store: PolicyStore, def: PolicyDef): bool =
  let cur = store.currentValue(def)
  result = cur.isSome and cur.get() == def.applyValue

proc statusOf*(store: PolicyStore, def: PolicyDef): string =
  let cur = store.currentValue(def)
  if cur.isNone:
    return "Not set"
  let src = store.valueSource(def.valueName)
  let val = if cur.get() == def.applyValue: "Set" else: "Other (" & $cur.get() & ")"
  val & " (" & src & ")"

# ---------------------------------------------------------------------------
# Mutations
# ---------------------------------------------------------------------------

proc apply*(store: PolicyStore, def: PolicyDef): bool =
  store.writeDword(def.valueName, def.applyValue)

proc revert*(store: PolicyStore, def: PolicyDef): bool =
  store.deleteValue(def.valueName)