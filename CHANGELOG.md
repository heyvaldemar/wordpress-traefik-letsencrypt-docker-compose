# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

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

[Unreleased]: https://github.com/heyvaldemar/wordpress-traefik-letsencrypt-docker-compose/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/wordpress-traefik-letsencrypt-docker-compose/releases/tag/v1.0.0
