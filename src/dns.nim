## DNS-over-HTTPS (Secure DNS) policy helpers.
##
## Chromium reads two string policies from the same Brave policy key:
##   DnsOverHttpsMode      = "off" | "automatic" | "secure"
##   DnsOverHttpsTemplates = a DoH template URL (required when mode = "secure")

import std/options
import winim/lean
import registry

const
  DnsModeValue* = "DnsOverHttpsMode"
  DnsTemplateValue* = "DnsOverHttpsTemplates"

  ModeOff* = "off"
  ModeAutomatic* = "automatic"
  ModeSecure* = "secure"

type
  DnsState* = object
    mode*: string
    templateUrl*: string
    hasMode*: bool
    hasTemplate*: bool

proc readDnsState*(store: PolicyStore): DnsState =
  result.mode = ModeAutomatic
  result.templateUrl = ""
  let m = store.readString(DnsModeValue)
  if m.isSome:
    result.hasMode = true
    result.mode = m.get()
  let t = store.readString(DnsTemplateValue)
  if t.isSome:
    result.hasTemplate = true
    result.templateUrl = t.get()

proc applyDns*(store: PolicyStore, mode: string, templateUrl: string): bool =
  ## Write the mode (and template when secure). Returns false on any failure.
  var ok = store.writeString(DnsModeValue, mode)
  if mode == ModeSecure:
    ok = store.writeString(DnsTemplateValue, templateUrl) and ok
  else:
    # Not needed for off/automatic; remove a stale template so Brave does not
    # keep using it.
    ok = store.deleteValue(DnsTemplateValue) and ok
  result = ok

proc revertDns*(store: PolicyStore): bool =
  var ok = store.deleteValue(DnsModeValue)
  ok = store.deleteValue(DnsTemplateValue) and ok
  result = ok

# ---------------------------------------------------------------------------
# Known DoH template providers
# ---------------------------------------------------------------------------

type
  Provider* = object
    name*: string
    templateUrl*: string
    note*: string

const
  # index 0 is always "Custom"
  Providers*: seq[Provider] = @[
    Provider(name: "Custom", templateUrl: "",
      note: "Enter a DoH template URL, e.g. https://dns.nextdns.io/<ID>"),
    Provider(name: "Cloudflare", templateUrl: "https://cloudflare-dns.com/dns-query",
      note: "Cloudflare DNS"),
    Provider(name: "Google", templateUrl: "https://dns.google/dns-query",
      note: "Google Public DNS"),
    Provider(name: "Quad9", templateUrl: "https://dns.quad9.net/dns-query",
      note: "Quad9"),
    Provider(name: "AdGuard", templateUrl: "https://dns.adguard-dns.com/dns-query",
      note: "AdGuard DNS"),
    Provider(name: "NextDNS", templateUrl: "https://dns.nextdns.io/",
      note: "NextDNS - append your configuration ID, e.g. https://dns.nextdns.io/abc123"),
  ]