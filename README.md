# CatExplorer

An experimental project to wrap any website into a standalone iOS IPA. Point it at a URL, customize behavior via a single JSON config, optionally inject JavaScript per-site, and build a self-contained app with Theos.

> **⚠️ Experimental** — This is a personal/research project. Expect rough edges.

## Building

Requires [Theos](https://theos.dev).

```bash
make package FINALPACKAGE=1
```

## Configuration

Everything lives in `Resources/config.json`:

```json
{
    "url": "https://www.google.com",
    "pullToRefresh": true,
    "userAgent": "",
    "headers": {},
    "entitlements": []
}
```

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `url` | `string` | `https://www.google.com` | The website to load. Navigation is scoped to this domain — external links open in Safari. |
| `pullToRefresh` | `bool` | `true` | Enable pull-to-refresh on the webview. |
| `external_navigation_in_default_browser` | `bool` | `true` | If true, user taps on external domain links open in the default browser iOS app (e.g. Safari). If false, external domains load inside the webview. |
| `userAgent` | `string` | `""` | Custom User-Agent string. Empty uses WKWebView's default. |
| `headers` | `object` | `{}` | Custom HTTP headers sent with every request. Keys are header names, values are header values. |
| `entitlements` | `array` | `[]` | iOS entitlement keys to include at build time. Each string becomes a `<true/>` entry in the generated entitlements plist. |

### Entitlements example, just examples, these are not going to have any effect on the wkwebview process

```json
{
    "entitlements": [
        "com.apple.developer.kernel.increased-memory-limit",
        "com.apple.developer.kernel.extended-virtual-addressing"
    ]
}
```

## JavaScript Injection

Drop `.js` files into `Resources/js/` using a folder hierarchy that controls where they run. Scripts are indexed at build time into `scripts.json` and injected at runtime after each page load — no config entries needed, just the files.

### Directory structure

```
Resources/js/
├── all/                        # Injected on EVERY page
│   └── analytics_block.js
├── google.com/
│   ├── strict/                 # Only google.com and www.google.com
│   │   └── dark_mode.js
│   └── wildcard/               # google.com + *.google.com (maps, mail, etc.)
│       └── tracking_fix.js
└── example.org/
    └── strict/
        └── custom.js
```

### Modes

| Mode | Matches | Example for `google.com` |
|------|---------|--------------------------|
| `all/` | Every page regardless of domain | — |
| `strict/` | Exact domain + `www.` prefix only | `google.com`, `www.google.com` |
| `wildcard/` | Domain + all subdomains | `google.com`, `mail.google.com`, `maps.google.com` |

### How it works

1. **Build time** — `gen_scripts.sh` scans the `Resources/js/` tree and writes `Resources/scripts.json` with each script's path, target domain, and mode.
2. **App startup** — The app reads `scripts.json` once and pre-loads all JS source into memory.
3. **Each navigation** — After a page finishes loading, scripts matching the current URL's host are injected via `evaluateJavaScript:`.


## License

MIT
