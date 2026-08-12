# Vendored libsmb2

This directory is based on https://github.com/sahlberg/libsmb2 at commit:

```text
0b2aa4310c7a0510c666fe7da0eebce0f7e93824
```

It is distributed under LGPL-2.1; see `LICENCE-LGPL-2.1.txt`.

## Local modification

`lib/aes_apple.c` defines `kCCAlgorithmAES` as `kCCAlgorithmAES128` when the
former is unavailable. The compatibility alias is required by the
iPhoneOS 8.4 CommonCrypto headers used for the armv7 target.

When updating this dependency, preserve or re-evaluate that compatibility
patch and update the commit recorded here and in `THIRD_PARTY_NOTICES.md`.
