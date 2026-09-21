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

Build and run the local ad-hoc signed app:

    $ ./script/build_and_run.sh

The bootstrap script records dependency versions in each installation prefix,
so an existing checkout is rebuilt automatically when a pinned version changes.
Telephone-specific PJSIP patches live in `ThirdParty/PJSIP/patches`.

## Contribution

For the legal reasons, pull requests are not accepted. Please feel
free to share your thoughts and ideas by commenting on the issues.
