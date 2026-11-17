# Governance and responsibility

`4alvit` is the primary maintainer of the OTTPlay Roku client, its sideload
packages and release metadata. The maintainer owns review and merge decisions,
release acceptance, dependency maintenance, private security reports and conduct
enforcement. Contributors propose changes in public issues and pull requests and
provide appropriate tests. Automation supplies diagnostics and may submit
eligible reviews; it does not replace maintainer accountability or provide
independent human continuity.

Discuss technical decisions in the relevant issue or pull request. The maintainer
resolves disagreement using project scope, compatibility, test evidence, security
and maintenance cost. Contributors may request reconsideration with new evidence.
Security and conduct reports use the private channels in SECURITY.md and
CODE_OF_CONDUCT.md. Normal checks and review apply to changes; no administrative
bypass is part of this policy. Source release, sideload packaging and Roku Beta
submission are separate actions with their own acceptance requirements.

Roku, the Roku Store and the Beta app program set their own signing, review and
distribution terms; see [release and signing](docs/release.md).

## Continuity limitation

There is no designated backup maintainer and no tested process to restore
repository, CI and release access within one week if the maintainer is unavailable.
A bot account, this document and possible account recovery do not satisfy access
continuity or a two-person bus factor. Both requirements remain unmet.
