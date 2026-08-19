# Fonts — provenance & license

This site self-hosts both typefaces under `assets/fonts/`. No Google Fonts CDN, no
external font requests at all — matches the app repo's own no-font-CDN rule
(SPEC F28.3). Every request this page makes is same-origin.

| File | Family | Style | Weight | Bytes |
|---|---|---|---|---|
| `fraunces-variable-latin.woff2` | Fraunces | normal | 400 & 600 (variable) | 36,620 |
| `fraunces-italic-variable-latin.woff2` | Fraunces | italic | 400 & 600 (variable) | 45,656 |
| `source-sans-3-variable-latin.woff2` | Source Sans 3 | normal | 400 & 600 (variable) | 28,740 |

Both families ship as variable fonts on the `wght` axis, so one file each covers
weights 400 and 600 — the `@font-face` rules in `assets/css/style.css` declare both
weights against the same `src` (this is a normal, browser-supported pattern for
variable fonts; Google's own CDN serves the identical file for both weight requests).

## License

Both families are licensed under the **SIL Open Font License 1.1** (`OFL-1.1`) —
free to embed, self-host, and redistribute, including in a project whose own code is
under a different license (this repo is MIT; the app repo is AGPL-3.0).

- **Fraunces** — <https://github.com/undercasetype/Fraunces> (canonical upstream, OFL-1.1)
- **Source Sans 3** — <https://github.com/adobe-fonts/source-sans> (canonical upstream, OFL-1.1)

Full license text: <https://openfontlicense.org/open-font-license-official-text/>

## Fetch provenance

Fetched once from Google Fonts' CDN (`fonts.gstatic.com`) on 2026-08-19 via the
`css2` API's `latin`-subset variable-font URLs, then committed — no runtime
dependency on Google's servers remains. Exact source URLs, for audit:

```
https://fonts.gstatic.com/s/fraunces/v38/6NUu8FyLNQOQZAnv9bYEvDiIdE9Ea92uemAk_WBq8U_9v0c2Wa0K7iN7hzFUPJH58nib14c7qv8.woff2
https://fonts.gstatic.com/s/fraunces/v38/6NUs8FyLNQOQZAnv9ZwNjucMHVn85Ni7emAe9lKqZTnbB-gzTK0K1ChJdt9vIVYX9G37lvd9mv0iQg.woff2
https://fonts.gstatic.com/s/sourcesans3/v19/nwpStKy2OAdR1K-IwhWudF-R3w8aZQ.woff2
```

Resolved by requesting:

```
https://fonts.googleapis.com/css2?family=Fraunces:ital,wght@0,400;0,600;1,400;1,600&display=swap
https://fonts.googleapis.com/css2?family=Source+Sans+3:wght@400;600&display=swap
```

with a browser User-Agent (Google serves woff2 + resolves the `latin` unicode-range
subset only for User-Agents it recognizes as modern), then downloading each distinct
`url(...)` referenced by the returned CSS. The naming convention
(`{family}[-italic]-variable-latin.woff2`) matches the app repo's own vendored-font
convention (see the app repo's `FONTS.md`) for consistency across both properties,
though this site has no build-time subsetting pipeline of its own — the files above
are exactly what Google's CDN served, unmodified.
