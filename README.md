Telephone is a VoIP SIP softphone for Mac. It allows you to make phone
calls over the Internet or your company network. If your phone line
supports SIP protocol, you can use it on your Mac instead of a
physical phone anywhere you have a decent network connection.

## Building

The personal fork currently targets Apple silicon and macOS 15.6 or newer.

Third-party dependencies are pinned and built by the repository bootstrap
script:

- Opus 1.5.2
- LibreSSL 4.3.2
- PJSIP 2.17

Build the dependencies:

    $ ./script/bootstrap_third_party.sh

Build Telephone:

    $ ./script/build.sh Debug

Build and run the local app:

    $ ./script/build_and_run.sh

CI uses ad-hoc signing. For repeated local development, create a stable self-signed
code-signing identity once so macOS Keychain/TCC can recognize subsequent builds:

    $ bash ./script/create_local_signing_identity.sh
    $ export TELEPHONE_CODE_SIGN_IDENTITY="Telephone Local Development"
    $ ./script/build_and_run.sh

This identity is local to your Mac and does not require an Apple Developer
Program membership. If `TELEPHONE_CODE_SIGN_IDENTITY` is unset, the build
scripts fall back to ad-hoc signing.

The bootstrap script records dependency versions in each installation prefix,
so an existing checkout is rebuilt automatically when a pinned version changes.
Telephone-specific PJSIP patches live in `ThirdParty/PJSIP/patches`.

## Personal fork workflow

This fork is maintained as a personal macOS build. Development happens only in
`pvl-grdv/Telephone`; the original `64characters/Telephone` repository is treated
as read-only upstream and this fork does not open pull requests against it.

Use short-lived `work/<topic>` branches, let CI run unit tests and the app build,
then integrate the validated result into `master` as one clean logical commit.
A pull request is not required for the normal solo-development workflow.

Detailed agent rules are in `AGENTS.md`.

## Contribution

For legal reasons, pull requests to the original project are not accepted. Please
feel free to share thoughts and ideas in the original project's issue tracker.
