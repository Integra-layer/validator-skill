# Changelog

## [1.0.0] - 2026-02-12

### Added
- Claude Code plugin structure with `.claude-plugin/plugin.json`
- 4 skills: deploy-validator, validator-ops, setup-caddy, generate-connect-page
- 3 reference docs: network-config, security-hardening, troubleshooting
- Templates for Docker, systemd, Caddy, connect page, network deployment
- Connect page templates with `{{VARIABLE}}` placeholders for scaffolding validator landing pages

### Fixed
- Go version updated from 1.22 to 1.25 in prerequisites script
- systemd service now runs as `integra` user instead of `root`
- Docker Compose files include healthcheck
- Keyring backend aligned to `test` in network deploy config

### Changed
- Restructured from monolithic SKILL.md into 4 focused skills
- Moved Docker files to `templates/docker/`
- Moved deployment scripts to `templates/network-deploy/`
- Moved systemd service to `templates/systemd/`
