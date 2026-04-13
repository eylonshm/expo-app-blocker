# Security Policy

## Scope

`expo-app-blocker` is a client-side Expo native module. It has no server components, no network requests, and no data collection. Security concerns are most likely to involve:

- Unsafe handling of app tokens or opaque selection data
- Bypassable blocking behavior (iOS shield dismissal, Android overlay escapes)
- Improper use of entitlements or Android permissions
- Dependency vulnerabilities

## Reporting a Vulnerability

**Please do not report security vulnerabilities via public GitHub issues.**

Report vulnerabilities privately using [GitHub's private vulnerability reporting](https://github.com/eylonshm/expo-app-blocker/security/advisories/new).

Include as much of the following as possible:

- Description of the vulnerability and potential impact
- Steps to reproduce or proof-of-concept
- Affected versions
- Platform (iOS / Android) and OS version
- Suggested fix, if you have one

You can expect an acknowledgement within 72 hours. We'll keep you updated as we investigate and patch.

## Supported Versions

Only the latest published version on npm receives security fixes. We recommend always staying up to date.
