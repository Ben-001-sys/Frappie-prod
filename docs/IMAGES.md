# Published proof-of-concept images

Both images built successfully in GitHub Actions run 41335556780 and passed container inspection in verification run 41338561204 on 2026-11-01.

**Source commit (image-build configuration):** `75e3b8f5c0cb6ce1fb152efe73657c31789572e0`

## Suite (same exact image on application and worker hosts)

```text
ghcr.io/ben-001-sys/frappie-suite@sha256:06935660af52833122ed4b982b6c0504144e21d95b483f81042529c372006e20
```

Contains Frappe Framework (v15 branch), ERPNext, HRMS, CRM, Helpdesk, LMS and Raven; **the original image lacks Telephony and Payments and failed the Suite installation smoke test. Do not deploy this digest.** A corrected build is in progress or pending. Note: currently v15 for Frappe/ERPNext/HRMS; other apps reference `main`, not pinned commits.

## Insights (independent site)

```text
ghcr.io/ben-001-sys/frappie-insights@sha256:1d38d782b9a3c9d03ed5051c4eff7ca8a232a8f33094bd2018ae5cb62e24cee4
```

Contains Frappe Framework v15 and Insights v3 branch.

## Verification scope

The first verification checked that GitHub runners could pull the published images and that the expected app code directories existed. The **new installation smoke-test workflow** creates a temporary database and installs the apps with Bench to test version compatibility. It does not prove multi-host NFS, application functionality, secure deployment or production suitability.

Do not use mutable GHCR tags in Dokploy deployment settings. The Suite digest listed above is BLOCKED pending a new successful eight-app build and full Bench installation test. The Insights digest passed its initial installation test.

- [Build run](https://github.com/Ben-001-sys/Frappie-prod/actions/runs/41335556780)
- [Container verification run](https://github.com/Ben-001-sys/Frappie-prod/actions/runs/41338561204)
