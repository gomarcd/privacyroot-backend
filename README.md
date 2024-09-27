# Privacyroot

The idea for Privacyroot is to provide an easy way to spin up a new privacy oriented service in a quickly repeatable, containerized way without needing to contend with all the complexities under the hood that used to be a requirement.

## Technology

The stack consists of Postfix, Dovecot, OpenDKIM and SQLite.

Designed to run as a single Docker container that can be easily deployed on any server and includes Unbound, Nginx, and a CLI script for administration.

## Privacy

Gmail revolutionized email with convenience at the expense of privacy.

Proton Mail revolutionized email by bridging a gap between privacy and convenience, but its PGP encryption by default mostly only works on email sent to and from Proton Mail.

Privacyroot improves on the interoperability. Any mail sent between Proton and Privacyroot - or any other WKD enabled provider - will be PGP encrypted by default.

:white_check_mark: Automatic outbound PGP encryption when [WKD](https://wiki.gnupg.org/WKD?ref=uriports.com#Implementations) discovery finds a key
:white_check_mark: Automatically encrypt inbound mail with user PGP pubkey
:white_check_mark: Password-derived mailbox encryption at rest with Dovecot
:white_check_mark: Autodiscovery/autoconfiguration
:white_check_mark: CLI admin script