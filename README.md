# imap-email-notifier

![GitHub top language](https://img.shields.io/github/languages/top/mikkun/imap-email-notifier)
![GitHub release (latest by date)](https://img.shields.io/github/v/release/mikkun/imap-email-notifier)
![GitHub license](https://img.shields.io/github/license/mikkun/imap-email-notifier)

> :mailbox: Email notifier for IMAP mailboxes

## Description

This script connects to an IMAP server, retrieves unread messages from specified folders, and sends notification emails about new unread messages via an SMTP server.

## Requirements

- [Perl](https://www.perl.org/) (&gt;= 5.12.0)
- [cpanm](https://github.com/miyagawa/cpanminus)
- [Carton](https://github.com/perl-carton/carton)
- [OpenSSL](https://www.openssl.org/)/[LibreSSL](https://www.libressl.org/) headers
- [zlib](https://zlib.net/) headers

## Installation

### Install the build dependencies

```shell
# Debian-based distributions
sudo apt install build-essential
sudo apt install libssl-dev zlib1g-dev

# Fedora-based distributions
sudo dnf groupinstall "Development Tools" "Development Libraries"
sudo dnf install openssl-devel zlib-devel

# Arch-based distributions
sudo pacman -S base-devel
sudo pacman -S openssl zlib
```

### Install cpanm

```shell
# Debian-based distributions
sudo apt install cpanminus

# Fedora-based distributions
sudo dnf install cpanminus

# Arch-based distributions
sudo pacman -S cpanminus
```

### Install Carton

```shell
sudo cpanm Carton
```

### Clone the repository

```shell
git clone https://github.com/mikkun/imap-email-notifier.git
```

### Install dependent modules

```shell
cd imap-email-notifier
carton install --deployment
```

## Usage

```shell
./imap-email-notifier.pl
```

## Options

There are no command-line options for this script. Configuration should be done within the script.

## Configuration

The configuration information is stored in the `$CONFIG` hash within the script.

## License

[Artistic License 2.0](./LICENSE)

## Author

[KUSANAGI Mitsuhisa](https://github.com/mikkun)

## References

- [Mail::IMAPClient](https://metacpan.org/pod/Mail::IMAPClient)
- [Net::SMTP](https://metacpan.org/pod/Net::SMTP)
