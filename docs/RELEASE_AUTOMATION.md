# Release automation setup

The `Release macOS app` workflow publishes a notarized ZIP when a `v*` tag is
pushed. It runs in the protected GitHub `release` environment, so configure
reviewers there before adding its secrets.

Add these environment secrets:

| Name | Value |
| --- | --- |
| `DEVELOPER_ID_CERTIFICATE` | Base64-encoded Developer ID Application `.p12` file. |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used to export that `.p12` file. |
| `APPLE_API_KEY_ID` | App Store Connect API key ID. |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer ID. |
| `APPLE_API_PRIVATE_KEY` | Full contents of the App Store Connect API key `.p8` file. |

Add the repository variable `DEVELOPER_ID_APPLICATION_IDENTITY` with the exact
certificate name, for example `Developer ID Application: Example, Inc. (TEAMID)`.
The certificate's Team ID must match the signing identity. The generated
application is notarized with the API key, stapled, verified by Gatekeeper, and
uploaded as `TeamsLight-macOS.zip`.

Create a release only after CI is green:

```sh
git tag v1.0.0
git push origin v1.0.0
```

You can also run the workflow manually, but provide an existing `v*` tag. Test
the workflow in a private fork or with a prerelease tag first. Treat the
certificate and API-key material as secrets; never commit either file.
