# Portfolio Visitor Tracking — Extended Implementation Summary (v4)

## Overview
Extended existing static portfolio tracking/location system WITHOUT rebuilding. Preserved all existing DB/APIs/workflows/tracking/source detection/dashboard UI/portfolio functionality. Added reliability, bot detection, IP type, ISP/ASN, confidence, and privacy-aware dashboard labels.

---

## Files Changed

### 1. `index.html` — Tracking Core (Extended, Not Rebuilt)
**Preserved:**
- `SB_MM` Supabase client, `MM_FRAMED` iframe skip, `MM_VID` sequential V-#### via `next_visitor_id` RPC, `mmCanonicalSource`/`mmSource` source detection, `mmCleanPath`, 30min view dedup via `mm_last_view`, `?mmloc` debug probe, event queue.

**Added / Extended:**
- **MM_LOC_SERVICES**: Added `ip-api.com` as first provider with `fields=status,country,countryCode,regionName,city,isp,org,as,proxy,hosting,mobile,query` to get explicit `proxy`, `hosting`, `mobile` flags. Kept 7 other providers but extended readers to capture `org`, `asn`, `ip`, `proxy`, `hosting`, `tor`, `vpn`, `mobile`.
- **mmCleanLoc(o)**: Now keeps `isp`, `org`, `asn`, `ip`, plus booleans `proxy`, `hosting`, `mobile`, `tor`, `vpn`. Still strips junk like "unknown", truncates to 80 chars, never stores `[object Object]`.
- **Detection Keywords**: `MM_VPN_KEYWORDS`, `MM_HOSTING_KEYWORDS`, `MM_PROXY_KEYWORDS`, `MM_TOR_KEYWORDS` for heuristic detection when provider doesn't give flags.
- **mmDetectIpType(loc)**: Multi-signal IP classification:
  - Checks explicit booleans from ip-api.com / ipwho.is security.
  - Falls back to ISP/Org/ASN string keyword matching (vpn, nordvpn, expressvpn, protonvpn, surfshark, amazon, aws, google cloud, azure, digitalocean, hetzner, cloudflare, datacenter, proxy, tor, etc).
  - Returns `ip_type` = `residential` | `mobile` | `vpn` | `proxy` | `tor` | `hosting` | `unknown`, plus flags `vpn_detected`, `proxy_detected`, `tor_detected`, `hosting_detected`, `mobile_detected`, `location_confidence` (high/medium/low/unknown), `location_masked` (true when VPN/Proxy/Tor/Hosting).
- **mmGetUserAgent()**: Returns truncated UA (180 chars) for bot detection, no extra PII.
- **mmClassifyVisitorType()**: Multi-signal human vs bot classification (never single signal, marks Unknown if uncertain):
  - Lowercases UA, checks `navigator.webdriver`.
  - Patterns:
    - Bot/Crawler: googlebot, bingbot, yandex, baiduspider, duckduckbot, slurp, semrushbot, ahrefsbot, dotbot, mj12bot, etc.
    - Link Preview: facebookexternalhit, Facebot, Slackbot, Twitterbot, LinkedInBot, WhatsApp, TelegramBot, Discordbot, SkypeUriPreview, etc.
    - Scanner/Security: urlscan, VirusTotal, phishtank, safebrowsing, urlvoid, hybrid-analysis, CensysInspect, Shodan, nuclei, etc.
    - Automated: curl, wget, python-requests, go-http-client, axios, node-fetch, java/, libwww-perl, okhttp, postman, headlesschrome, phantomjs, selenium, puppeteer.
  - Human: browser UA (Chrome/Firefox/Safari/Edge/Opera + Mozilla) + not webdriver + residential/mobile IP = likely human. Hosting + browser = Unknown (contradiction).
  - Returns `visitor_type` = `human` | `bot` | `link_preview` | `scanner` | `automated` | `unknown`, confidence, signals (max 6).
- **mmLocationConfidence()** wrapper, **mmSaveLoc()** now caches enriched data (isp, org, asn, ip, proxy/hosting/mobile/tor/vpn, ip_type, location_confidence, via) in localStorage `mm_loc` TTL 6h.
- **mmTrack(event, meta)**: Now merges into meta:
  - Existing: city, region, country, country_code
  - New: isp, org, asn, ip_type, vpn_detected, proxy_detected, tor_detected, hosting_detected, mobile_detected, location_confidence, location_masked, location_is_estimate=true, location_note (masked warning), visitor_type, visitor_type_confidence, bot_signals, user_agent (180 chars), traffic_source (from mmSource, with source fallback). Clarifies Source=Link = direct URL access, NOT proof of sender.
  - Preserves late-location backfill row.
- **?mmloc debug**: Enhanced to show IP Type, Confidence, Masked warning, Visitor Type, Source, ISP/ASN, privacy disclaimer, per-service [ip_type/confidence].

**Privacy:**
- No GPS, no geolocation API, no coordinates, IP itself stored only as coarse text in meta (optional, truncated) and never as precise PII; ISP/ASN only. City = ISP gateway estimate, not exact physical location. Foreign country ≠ proof of real person. VPN/proxy may be network endpoint. Link source not proof.

### 2. `setup.sql` — Database Schema (Additive, No Deletion)
**Preserved:** All existing tables, functions, views, indexes, RLS policies, retention.

**Added:**
- **Generated columns** in `portfolio_events` (via DO blocks, only if not exists, so safe to re-run):
  - Text: `city`, `country`, `country_code` (existing), plus `isp`, `org`, `asn`, `ip_type`, `visitor_type`, `location_confidence`, `traffic_source` (coalesce traffic_source/source), `user_agent`, `region`, `visitor_type_confidence`, `bot_signals`
  - Boolean: `vpn_detected`, `proxy_detected`, `tor_detected`, `hosting_detected`, `mobile_detected`, `location_masked`, `location_is_estimate` (case when meta ? key then (meta->>key)::boolean)
- **Views extended at END** (rule: add columns only at END to avoid breaking existing views):
  - `site_visitors`: after `location`, adds `isp`, `org`, `asn`, `ip_type`, `visitor_type`, `visitor_type_confidence`, `location_confidence`, `traffic_source`, `user_agent`, `vpn_detected`, `proxy_detected`, `tor_detected`, `hosting_detected`, `location_masked` (all latest per visitor via array_agg).
  - `site_events_log`: after `location`, adds `isp`, `asn`, `ip_type`, `visitor_type`, `location_confidence`, `traffic_source`, `vpn_detected`, `proxy_detected`, `tor_detected`, `hosting_detected`, `location_masked`, `user_agent`.
- **New rollup views** (Table Editor only, revoked from anon):
  - `site_traffic_by_visitor_type`: visitors grouped by `visitor_type` (Human / Possible Bot / Possible Link Scanner / etc) — non-definitive.
  - `site_traffic_by_ip_type`: visitors grouped by `ip_type` (residential / mobile / vpn / proxy / tor / hosting / unknown) — estimate, may be masked.
  - `site_traffic_by_isp`: visitors grouped by ISP/ASN.
- **Indexes**: `portfolio_events_ip_type_idx`, `portfolio_events_visitor_type_idx`, `portfolio_events_isp_idx` plus existing `portfolio_events_location_idx`.
- **get_analytics(p_days)**: Extended:
  - `loc` CTE now includes isp, asn, ip_type, visitor_type, location_confidence.
  - New CTEs: `visitor_types`, `ip_types`.
  - `visitors` JSON now includes: city, region, country, country_code, isp, org, asn, ip_type, visitor_type, visitor_type_confidence, location_confidence, traffic_source, user_agent, vpn_detected, proxy_detected, tor_detected, hosting_detected, location_masked, visits, events, first_visit, last_seen, source.
  - Returns additional keys: `visitor_types`, `ip_types`, plus existing `days`, `totals`, `daily`, `top_project`, `sources`, `cities`, `countries`, `visitors`, `messages`.

### 3. `dashboard.html` — Analytics UI (Extended)
**Preserved:** Login, tabs, CRUD for portfolio content, preview, messages, existing analytics (totals, daily chart, sources, countries, visitors list, location check).

**Added / Fixed:**
- Fixed pre-existing bug: `secRows` undefined in `R.settings` — now generates checkboxes from `CONTENT.settings.sections`.
- **MM_LOC_SERVICES**: Now 8 services (added ip-api.com first) with richer readers capturing isp/asn/proxy/hosting. Mirrors index.html (keep both in sync).
- **mmAskService**: Now includes ISP/ASN/proxy/hosting in txt for probe.
- **loadLocCheck**: Shows coverage for country, ISP/ASN, visitor_type counts.
- **runLocProbe**: Notes VPN/Proxy/Hosting detection via ip-api.com, privacy disclaimer.
- **Labels**: `mmVisitorTypeLabel()` → Human / Possible Bot / Possible Link Preview / Possible Scanner / Possible Automated / Unknown (non-definitive). `mmIpTypeLabel()` → Residential / Mobile / VPN (possible) / Proxy (possible) / Tor (possible) / Data Center / Hosting / Unknown. `mmConfidenceLabel()` → High/Medium/Low/Unknown.
- **locationFromRows(rows)**: Parses new meta keys (isp, org, asn, ip_type, visitor_type, location_confidence, etc), builds rollups for cities, countries, visitor_types, ip_types, isps, and per-visitor enriched objects (including masked flags).
- **analyticsFromRows(rows, days)**: Same as get_analytics fallback, now also computes visitor_types, ip_types, isps from raw rows, canon source includes traffic_source.
- **loadAnalytics()**: 
  - Handles both RPC and raw fallback, merges locationFromRows if RPC lacks new keys.
  - Cards: adds Countries, Visitor Types, IP Types counts.
  - Sources panel: clarifies Source=Link/Direct = direct URL access, NOT proof of sender.
  - Country panel: keeps country ~99% reliable, city deliberately less emphasized, notes foreign country ≠ proof of real person, VPN may be endpoint, no GPS, no IP stored.
  - New panels: Visitor Type breakdown (non-definitive labels, multi-signal, Unknown if uncertain, bots can mislead), IP Type breakdown (Residential vs VPN/Proxy/Tor/Hosting, masked warning, never exact), ISP/ASN breakdown.
  - Visitors — detailed: each row shows:
    - VID, Country + City (flag), Source + (Source=Link note)
    - Chips: Visitor: Human/Possible Bot/etc (confidence), IP: Residential/Mobile/VPN/Proxy/Tor/Data Center + flags [VPN, Proxy, Tor, Data Center], Location Confidence: High/Medium/Low + ⚠️ possibly masked, ISP: isp / asn
    - Warning: if location_masked → "Location may be masked — IP appears to be VPN/Proxy/Tor/Hosting endpoint. City/Country is estimate of network exit, not exact physical location. Foreign country ≠ proof of real person."
    - Else: "IP-based estimate (city = ISP gateway, not exact). No GPS, no precise location. Treat as approximate."
  - Privacy banner at top of Analytics tab summarizing all limitations.
  - Preserves existing chart, top project, totals.

---

## Database Fields Added (All from meta, no deletion)

All fields are nullable, read from `meta` jsonb, backward compatible with old rows (old rows show null/unknown):

- `city`, `country`, `country_code` (existing, reused)
- `region` (text)
- `isp` (text) — ISP name, e.g. "Vodafone Egypt"
- `org` (text) — organization
- `asn` (text) — ASN number/name
- `ip_type` (text) — residential | mobile | vpn | proxy | tor | hosting | unknown (estimate, may be masked)
- `visitor_type` (text) — human | bot | link_preview | scanner | automated | unknown (non-definitive, multi-signal)
- `visitor_type_confidence` (text) — high | medium | low
- `bot_signals` (text) — comma-joined signals like "ua:googlebot, hosting asn"
- `location_confidence` (text) — high (residential+city) | medium (residential country or mobile+city) | low (VPN/Proxy/Tor/Hosting or no city) | unknown
- `traffic_source` (text) — coalesce traffic_source/source, full recognizable name (instagram/facebook/linkedin/direct/etc). Note: direct/Link = direct URL access, NOT proof of sender.
- `user_agent` (text) — truncated UA 180 chars for bot detection, no extra PII
- `vpn_detected` (boolean) — true if VPN signals found
- `proxy_detected` (boolean)
- `tor_detected` (boolean)
- `hosting_detected` (boolean) — data center / hosting / cloud
- `mobile_detected` (boolean)
- `location_masked` (boolean) — true when VPN/Proxy/Tor/Hosting detected → location may be masked
- `location_is_estimate` (boolean) — always true when location present, marks estimate

Reuse: `country`, `city` already existed.

---

## APIs / Services Used (Free, No Keys)

**IP Geolocation (city/country + ISP/ASN + flags):**
- `https://ip-api.com/json/?fields=...` — primary for proxy/hosting/mobile detection (free tier 45 req/min, no key, https). Returns proxy, hosting, mobile, isp, org, as, query, city, regionName, country, countryCode.
- `https://ipwho.is/` — fallback, parses `connection.isp`, `connection.asn`, `security.proxy/vpn/tor/hosting`.
- `https://ipapi.co/json/` — fallback, org, asn.
- `https://free.freeipapi.com/api/v1/json` — fallback.
- `https://api.ip.sb/geoip` — fallback.
- `https://get.geojs.io/v1/ip/geo.json` — fallback.
- `https://wtfismyip.com/json` — fallback.
- `https://api.my-ip.io/v2/ip.json` — last resort country only.

**Logic:** Ask in parallel chain with per-provider timeout 2000ms, overall wait max 1500ms for events (never blocks visit count). Cache in localStorage `mm_loc` 6h. Probe function `mmLocProbe()` for `?mmloc` self-test.

**Supabase:**
- Existing: `next_visitor_id` RPC for sequential V-####, `portfolio_events` insert, `get_analytics` RPC, `portfolio_messages`.
- Extended `get_analytics` now returns visitor_types, ip_types, isps, enriched visitors.

---

## Detection Logic

### Location Reliability
- Keep IP-based country/city estimate (city = ISP gateway, not device position). Example: visitor in Asyut/Sohag can read as Cairo.
- Never claim exact physical location, never GPS, never coordinates.
- Add IP type detection:
  - Explicit flags from ip-api.com (proxy, hosting, mobile) and ipwho.is security.
  - Heuristic keyword scan on ISP/Org/ASN: VPN keywords (nordvpn, expressvpn, protonvpn, surfshark, mullvad, wireguard, openvpn, etc), Hosting keywords (amazon, aws, google cloud, azure, digitalocean, hetzner, cloudflare, datacenter, etc), Proxy keywords, Tor keywords.
  - Classify ip_type: tor > proxy > vpn > hosting > mobile > residential > unknown.
- Store ISP/ASN as text (helps spot hosting/VPN).
- location_confidence:
  - High: residential + city present, no masking.
  - Medium: residential/mobile with country but city missing or mobile+city.
  - Low: any masking (VPN/Proxy/Tor/Hosting) or only country or no city or unknown ip_type.
- Mark `location_masked` true when VPN/Proxy/Tor/Hosting detected → dashboard shows ⚠️ possibly masked, note "Location may be masked (VPN/Proxy/Tor/Hosting endpoint) - IP-based estimate only, not exact physical location".
- Never invent location, treat as estimate.

### Traffic Source Detection (Preserved + Clarified)
- Preserve `mmCanonicalSource`: maps utm_source, fbclid, referrer hostname to full recognizable name: instagram, facebook, linkedin, twitter, whatsapp, telegram, youtube, tiktok, reddit, github, email, or full hostname (google.com), else direct.
- Preserve `mmSource()`: checks utm_source, fbclid, referrer (if not same hostname), else direct.
- Clarify in UI: Source=Link/Direct only means accessed via direct URL or link, NOT proof of who sent link. Foreign country not proof of real person. Added banners in dashboard.

### Human vs Bot/Scanner Detection (Multi-Signal, Unknown if Uncertain)
- Never rely on single signal. Mark Unknown if cannot confidently determine. Never claim definitely bot/VPN/specific physical location unless data can establish.
- Signals:
  - User-Agent patterns (lowercased):
    - Bot/Crawler: googlebot, bingbot, yandex, baiduspider, duckduckbot, slurp, semrushbot, ahrefsbot, dotbot, mj12bot, rogerbot, exabot, ia_archiver, etc.
    - Link Preview: facebookexternalhit, Facebot, Slackbot, Twitterbot, LinkedInBot, WhatsApp, TelegramBot, Discordbot, SkypeUriPreview, etc.
    - Scanner: urlscan, VirusTotal, phishtank, safebrowsing, urlvoid, hybrid-analysis, CensysInspect, Shodan, nuclei, zgrab, etc.
    - Automated: curl, wget, python-requests, go-http-client, axios, node-fetch, java/, libwww-perl, okhttp, postman, headlesschrome, phantomjs, selenium, puppeteer, playwright, webdriver.
  - IP/ASN: hosting/data center + bot UA → higher confidence bot. Residential + browser UA → likely human. Hosting + human UA → Unknown (contradiction).
  - Behavior: navigator.webdriver flag, empty UA, unrecognized UA → Unknown/low confidence.
- Output: visitor_type = human | bot | link_preview | scanner | automated | unknown, with confidence high/medium/low and up to 6 signals stored as bot_signals.
- Dashboard labels non-definitive: Human, Possible Bot, Possible Link Preview, Possible Scanner, Possible Automated, Unknown.

---

## Dashboard Extensions

- **Analytics tab header**: Privacy & Reliability banner summarizing all limitations (IP-based estimate, Source=Link not proof, foreign country ≠ real person, VPN/proxy may be network endpoint, bots can mislead, never GPS, never invent, non-definitive labels).
- **Totals**: Visits, Unique visitors, Project opens, CV downloads, GitHub clicks, LinkedIn clicks, Form submits, Countries, Visitor Types, IP Types, Messages.
- **Where visitors came from**: Bar list, with note about Link not proof.
- **Where visitors are by country**: Flag + country + visitors + visits, with note about estimate, city is ISP gateway, VPN reads as VPN city, foreign country may be VPN endpoint.
- **Visitor Type panel**: Human / Possible Bot / Possible Link Preview / Possible Scanner / Automated / Unknown, with counts, non-definitive, multi-signal note.
- **IP Type panel**: Residential / Mobile / VPN (possible) / Proxy (possible) / Tor (possible) / Data Center / Hosting / Unknown, with masked warning.
- **ISP / ASN panel**: Top 10 ISPs with ASN, visitors.
- **Visitors — detailed**: Each visitor card shows VID, Country+City, Source (with Link clarification), chips for Visitor Type (confidence), IP Type + flags [VPN, Proxy, Tor, Data Center], Location Confidence + masked warning, ISP/ASN, plus masked warning text or estimate disclaimer. Includes first_visit, last_seen, visits, events, time ago.
- **Location check**: Enhanced coverage counts (country, ISP/ASN, visitor type), probe shows ISP/ASN/proxy/hosting per service, privacy note.

---

## Privacy & Limitations (Explicit in UI)

- **No GPS**, no browser location permission, no coordinates stored, IP itself not saved as precise PII (only coarse ISP/ASN text).
- **City/Country = estimate**: City is ISP gateway, not exact physical location. All Upper Egypt can read as Cairo on Egyptian lines. Treat as approximate.
- **VPN/Proxy/Tor/Hosting**: When detected, location is flagged Low confidence and "possibly masked" — shows network exit location, not user device. VPN/proxy may be corporate network endpoint.
- **Source=Link/Direct**: Only means accessed via direct URL or link, does NOT prove who sent link.
- **Foreign country ≠ proof of real person**: May be VPN endpoint, hosting, or scanner.
- **Bots/Scanners can mislead**: Link previews, security scanners, crawlers can generate visits from data centers.
- **Never invent**: If cannot confidently determine visitor_type or ip_type, mark Unknown. Do not claim definitely bot/VPN/specific physical location unless data can establish.
- **Free IP services**: Rate limited (~1k/day per service), may be blocked by ad blockers (uBlock, Brave, Firefox ETP). Visits still counted, only city missing. `?mmloc` and dashboard "Test location lookup" show which services answer in current browser.
- **User-Agent**: Can be spoofed; used as one signal among many, not sole proof.
- **ISP/ASN keyword heuristics**: May misclassify; labeled "possible" for VPN/Proxy/Tor.
- **Backward compatibility**: Old rows without new fields show as Unknown / no ISP.

---

## Preservation

- Existing DB, APIs, workflows, visitor tracking, traffic-source detection, dashboard UI, portfolio functionality preserved.
- All new columns additive, generated from meta, safe to re-run setup.sql (checks if column exists).
- All new dashboard panels additive, fallback to raw events if get_analytics RPC unavailable.
- No breaking changes to index.html rendering, theme, Portfolio Control, contact form, CV download, project galleries.

---

## How to Apply DB Changes

1. Supabase Dashboard → SQL Editor → New query → paste `setup.sql` → Run.
2. Notices will show added columns and view counts.
3. New fields appear in Table Editor: `portfolio_events` now has `isp`, `ip_type`, `visitor_type`, etc., and views `site_visitors`, `site_events_log`, `site_traffic_by_visitor_type`, `site_traffic_by_ip_type`, `site_traffic_by_isp`.
4. No data loss — old rows remain, new tracking enriches future events.

## Testing

- Open live site with `?mmloc` → probe panel shows location, IP Type, Confidence, Visitor Type, ISP/ASN, masked warning.
- Dashboard → Analytics → Refresh → see new panels.
- Dashboard → Location check → Test lookup → see 8 services probe.
