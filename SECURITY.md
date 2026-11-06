# Security

Please report vulnerabilities through [GitHub's private reporting](https://github.com/ardasnturk/mrradar/security/advisories/new).

* MRRadar never handles your password or OAuth token; `rc` does.
* An API key you paste stays in your Keychain.
* The hub listens on 127.0.0.1 and needs the token from a `0600` file.
* Cached reports stay in `~/Library/Application Support/MRRadar`.
