# Tested staging image release — 2026-11-01

**Release classification:** successful build, registry pull, basic directory verification, and *disposable site installation + migration*. **Not production-certified.**

**Image-source commit:** `3a0744e1571298e7f89a716539db4b1c32346137`

| Evidence | GitHub Actions | Result |
|---|---|---|
| Build and GHCR publication | [41341240098](https://github.com/Ben-001-sys/Frappie-prod/actions/runs/41341240098) | Both successful |
| Pull/image contents | [41343888063](https://github.com/Ben-001-sys/Frappie-prod/actions/runs/41343888063) | Both successful |
| **Bench installation + migration** | [41343888317](https://github.com/Ben-001-sys/Frappie-prod/actions/runs/41343888317) | Both successful |

## Operational Suite — same immutable digest for Application and Worker

```text
ghcr.io/ben-001-sys/frappie-suite@sha256:aad7925a4b03639aa3834d53098b2c09b7a7fd46c7486faace6d9e142a132a8c
```

Bench installation passed for ERPNext, HRMS, CRM, Telephony, Helpdesk, Payments, Learning (`lms`) and Raven. The **six business-facing apps** are ERPNext, HRMS, CRM, Helpdesk, Learning and Raven. Telephony and Payments are supporting required apps; all eight are packaged in the *same site*, not eight sites.

## Insights — separate image, separate Frappe site

```text
ghcr.io/ben-001-sys/frappie-insights@sha256:0805634533566ab52f32b1348358c6be7ae240bfcf0378a9f96743ca9fc14d6c
```

Bench installation and migration passed for Insights v3. The Insights site's operational database must remain separate from the ERPNext site's MariaDB database.

## Superseded — do not deploy

The original Suite digest `sha256:06935660af52833122ed4b982b6c0504144e21d95b483f81042529c372006e20` failed the Helpdesk smoke install due to missing Telephony, and lacked Learning's Payments dependency. Do not deploy or reintroduce the old Suite digest.

## Limitations and release gates

- These images were assembled from **mutable upstream branches**, not immutable upstream application commits. Record and pin exact app revisions for production reproducibility.
- Staging on actual OVHcloud VMs and managed NFS, private MariaDB/Redis connectivity, file upload, WebSocket, job processing, and restart/outage recovery are not yet tested.
- Backup/PITR and restore exercises, secret-handling, SSL/TLS, user permissions and approved operations must pass before production.
- Always deploy by the immutable `@sha256:` references above. Do not confuse the image-source commit with the latest repo HEAD, which also includes unrelated infrastructure changes.

## Source of truth

`release/verified-staging.json` is the machine-readable companion to this document. Environment examples should match it exactly. A new image-build run does **not** automatically become the approved staging release: rerun all relevant tests and deliberately update this record.
