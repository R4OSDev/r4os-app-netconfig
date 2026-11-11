# NETCFG.R4X

`NETCFG.R4X` is an independent R4OS application implemented in Zig.

## Package

- Package version `0.1.10`
- Image target: `/R4OS/SOFTWARE/DESKTOP/NETCFG.R4X`
- Image scope: `full`
- Canonical project manifest: `module.R4MF`

The manifest is the single source of truth for the artifact, imports, image
target, and package metadata.

## Build

On Windows:

    Build.bat

On Linux

    ./Build.sh

The build starters resolve the current local R4OS dependency checkouts through
`Settings.R4S`. The URL and hash entries in `build.zig.zon` record the
last verified standalone dependency identities; workspace builds use the
mapped local checkouts.

## Documentation

Detailed German technical notes from the migration are preserved in
`DOCUMENTATION.de.txt`. Source-transfer provenance is recorded in
`PROVENANCE.txt`.

## License

Original R4OS material is licensed under Apache License 2.0. See `LICENSE`
and `NOTICE`. Any repository-specific external material is documented in
`THIRD_PARTY_NOTICES.md`.

0.85.44: Rebuilt with SDK0.64.57 and the shared R4STD Unicode17.0.0
extended grapheme editing boundaries. Byte offsets, scalar font advances
and grapheme clusters are distinct; no shaping or BiDi support is implied.

## API migration 0.90.69

The normal build selects SDK202, App2, R4XStart2 and platform Query2.
The exact dependencies and ordered imports belong to module.R4MF.

The existing IPv4 fields and Defaults, Test, Apply, OK and Cancel remain.
Whole-form validation precedes mutation. Decimal components retain the
configuration owner's three-digit limit. Test sends the existing gateway
echo under a checked clock budget. Apply persists C:\CONFIG.R4S and applies
the live settings. The IPv6 view displays actual provider/interface data for
the uniquely matching adapter. Unknown and ambiguous identities stay unknown.
Font publication rebuilds Canvas/layout. Capture is cleared on focus loss
and input reset.
