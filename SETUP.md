# Quick setup

```bash
git clone https://github.com/jacobhammerle/todo-app.git && cd todo-app
npm install
npm install -g eas-cli
eas init && eas update:configure
```

Set your own `ios.bundleIdentifier` and `android.package` in [app.json](app.json); `eas init` does not change them.

Add two [secrets](https://docs.expo.dev/eas/environment-variables/) to the project's `production` environment on expo.dev:

- `CLAUDE_CODE_OAUTH_TOKEN`: the agent's credential, from [`claude setup-token`](https://code.claude.com/docs/en/authentication#generate-a-long-lived-token)
- `GITHUB_TOKEN`: a [fine-grained token](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens) with issues, pull requests, and contents write

Simulator sessions need no extra secret. The jobs start them with the token EAS gives every workflow run. Check that the account that owns the project has Expo Simulators with `eas simulator:availability`; a "Not authorized" from `simulator:start` means it does not. If your access comes through a different account (an organization you belong to, for example), add a [personal access token](https://docs.expo.dev/accounts/programmatic-access/) from that account as a third secret, `EXPO_TOKEN_SIMULATOR`. The scripts use it first whenever it is set.

Add one plain-text variable, `APP_VARIANT`, to each environment so the fingerprint jobs hash the same icons the builds use: `develop` in `development` and `preview`, `production` in `production`. Without it the fingerprint never matches a build and every workflow builds instead of reusing or repacking.

```bash
eas env:create development --name APP_VARIANT --value develop --visibility plaintext
eas env:create preview --name APP_VARIANT --value develop --visibility plaintext
eas env:create production --name APP_VARIANT --value production --visibility plaintext
```

For the `@expo-bot` helpers, add two GitHub repository secrets: `EXPO_TOKEN` (a [personal access token](https://docs.expo.dev/accounts/programmatic-access/)) and the same agent credential.

```bash
gh secret set EXPO_TOKEN
gh secret set CLAUDE_CODE_OAUTH_TOKEN
```

To rename the bot, change `botHandle` in package.json.

[Connect your GitHub repo](https://docs.expo.dev/eas/workflows/get-started/) under the project's settings on expo.dev, then push.

Try it:

```bash
eas workflow:run qa-swarm.yml
```

For the TestFlight loop, ship one build with `eas build -p ios --profile production --submit`, add yourself as a tester, and [connect the App Store Connect app](https://docs.expo.dev/eas/workflows/syntax/) on expo.dev.

## Or hand it off to your agent to get set up

Paste this into your coding agent from inside the cloned repo:

```text
Set up this repo on my own EAS project by following SETUP.md step by step.
Run the commands yourself. When a step needs a secret (CLAUDE_CODE_OAUTH_TOKEN
and GITHUB_TOKEN on EAS; EXPO_TOKEN and CLAUDE_CODE_OAUTH_TOKEN on GitHub),
stop and ask me for it; never make one up or print one back. After each
step, verify it: `eas whoami`, `eas simulator:availability`,
`eas env:list --environment production`, and `eas workflow:validate` on every
file in .eas/workflows/. Finish by running the QA swarm and telling me the
per-lane results.
```
