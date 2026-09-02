# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.1.0] - 2026-09-02

### Fixed

- **The data backup never ran.** The `tar` step referenced
  `DATA_BACKUP_PATH`, a variable the service does not define, so every
  cycle archived an empty path and moved on; the old loop reported
  nothing. It now archives `DATA_PATH` (the WordPress document root),
  and the new failure reporting is what surfaced this.
- **A failed database dump no longer produces a silent, corrupt backup.**
  The old loop piped the dump into `gzip` and only checked `gzip`'s exit
  status, so a dump that failed halfway (database down, wrong password,
  disk full) still left a small `.gz` that looked like a backup. The loop
  now runs with `pipefail`, logs `Database backup OK: <file> (<bytes>
  bytes)` or `Database backup FAILED` per cycle, keeps a failed dump as
  `<file>.failed` for diagnosis, and prunes only its own files. Retention
  set to `0` disables pruning instead of deleting everything.

### Added

- CI now waits for the first backup cycle and proves the produced
  archive is readable and contains a real dump header (plus a readable
  `tar.gz` for the data backup where the stack has one).

## [1.0.0] - 2026-08-31

First semver release. Brings this template to the fleet standard established
in [keycloak-traefik-letsencrypt-docker-compose](https://github.com/heyvaldemar/keycloak-traefik-letsencrypt-docker-compose)
v1.2.0.

### Changed (BREAKING for existing deployments)

- **WordPress switched from `bitnami/wordpress:latest` to the official
  `wordpress:7.1.0` image.** Bitnami's public Docker Hub images have been
  frozen since Broadcom's 2025 catalog change — the floating pin would
  have rotted forever. The official image uses different data paths
  (`/var/www/html` vs `/bitnami/wordpress`) and creates the admin via the
  web installer instead of environment variables. ❗ Existing deployments
  cannot switch images in place — see the release notes for the
  migration path (export content, fresh install, import).
- **MariaDB 11.1 (EOL short-term line) → 11.4 LTS**, **Traefik 3.2 → 3.7**
  (3.2's Docker client cannot talk to Docker Engine 29).
- **All three images pinned by `tag@sha256:digest`** in the compose
  `x-images` block.

### Security

- **Credentials untracked from git.** The tracked `.env` carried
  generated-looking database passwords — rotate them if reused.

### Added

- **Deployment Verification workflow**: shellcheck + actionlint; Trivy
  scans of all three pinned images; weekly `check-pin-freshness` (digest
  drift + WordPress Docker Hub tag lag + Traefik release lag);
  deploy-and-test that boots the full stack and requires the site to
  answer through Traefik.

### Fixed

- Shellcheck findings in both restore scripts.

[Unreleased]: https://github.com/heyvaldemar/wordpress-traefik-letsencrypt-docker-compose/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/heyvaldemar/wordpress-traefik-letsencrypt-docker-compose/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/heyvaldemar/wordpress-traefik-letsencrypt-docker-compose/releases/tag/v1.0.0
