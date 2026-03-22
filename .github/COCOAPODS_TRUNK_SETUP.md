# CocoaPods Trunk token (GitHub Actions)

The `publish-pods` workflow needs a valid **CocoaPods Trunk** token in the repository secret `COCOAPODS_TRUNK_TOKEN`.

## Add the secret

1. In GitHub: **Settings → Secrets and variables → Actions → New repository secret**
2. Name: `COCOAPODS_TRUNK_TOKEN`
3. Value: the token from your machine’s `~/.netrc` after registering with Trunk (see below).

## Register and obtain a token

1. Run locally: `pod trunk register YOUR_EMAIL "Your Name"`
2. Confirm the link in the email from CocoaPods.
3. After registration, your `~/.netrc` will contain the token used for `pod trunk push`.

If the token is missing or invalid, the workflow will fail at the “Authenticate with CocoaPods Trunk” step—update the secret with a fresh token from `~/.netrc` after a successful `pod trunk register`.
