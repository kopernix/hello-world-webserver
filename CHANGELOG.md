# Changelog

All notable changes to this project are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet.

## [0.1.0] - 2026-09-26

### Added

- HTTP and HTTPS server returning a fixed body and a fixed status code, both set
  from `.env` (`STATUS`, `BODY`, `HTTP_PORT`, `HTTPS_PORT`).
- Any status code from 100 to 999, including non-standard ones such as 499.
- Generic self-signed certificate under `tls/`, and `scripts/gen-cert.sh` to
  regenerate it.
- `scripts/test.sh`, smoke tests that run isolated from any live deployment.
- `AGENTS.md`, recording why each decision was made.

### Known limitations

- `container_name` is fixed, so two instances cannot run on the same Docker host.
- The committed certificate is a public test key and protects nothing.
- `BODY` accepts no double quotes, no newlines and no `$`.

[Unreleased]: https://github.com/kopernix/hello-world-webserver/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kopernix/hello-world-webserver/releases/tag/v0.1.0
