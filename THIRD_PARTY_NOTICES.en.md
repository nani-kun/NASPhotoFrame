# Third-Party Notices

## libsmb2

- Project: https://github.com/sahlberg/libsmb2
- Upstream commit: `0b2aa4310c7a0510c666fe7da0eebce0f7e93824`
- License: GNU Lesser General Public License 2.1
- Source directory: `ThirdParty/libsmb2`
- License file: `ThirdParty/libsmb2/LICENCE-LGPL-2.1.txt`

The repository retains the complete upstream source required to build the application. `lib/aes_apple.c` adds an iOS 8 compatibility definition so that the legacy CommonCrypto headers recognize the AES algorithm constant. See `ThirdParty/libsmb2/UPSTREAM.md` for details of the modification.

## GeoNames

- Project: https://www.geonames.org/
- Datasets: `cities15000` and `admin1CodesASCII`
- License: Creative Commons Attribution 4.0 International
- Derived file: `Resources/GeoNamesCities.sqlite3`
- Notice file: `Resources/GeoNames-LICENSE.txt`

The project includes a compact derived database for offline nearest-city lookups. The data is provided as-is, without any guarantee of accuracy, timeliness, or completeness.

## Apple Platform Components

The project links against system frameworks from the Apple SDK and invokes some private APIs on jailbroken devices. Apple SDKs, Xcode, and system frameworks are not distributed with this repository. Their use is governed by the applicable Apple license terms.
