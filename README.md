# Canon MF42x Remote UI Perl API

Small Perl client and CLI for Canon MF42x Remote UI.

Tested target:

- Canon MF421dw / MF420 Series
- User guide family: MF429x / MF428x / MF426dw / MF421dw
- Remote UI language: Russian

The public API is English. It does not depend on visible Remote UI labels. It uses stable Canon Remote UI endpoints and field names, so it can work while the printer UI language is Russian, English, or another supported language.

## Supported Features

- Detect Remote UI language cookie.
- Log in as System Manager.
- Read E-Mail/I-Fax network settings.
- Update E-Mail/I-Fax settings, including SMTP AUTH password.
- Fetch raw Remote UI pages for diagnostics.

## Requirements

- Perl 5
- Core/common Perl modules:
  - `HTTP::Tiny`
  - `URI::Escape`
  - `JSON::PP`
  - `Getopt::Long`

No CPAN-only dependency is required for the current feature set.

## CLI Examples

Check the Remote UI language:

```sh
bin/canon-mf42x --host 192.0.2.50 language --json
```

Check System Manager login:

```sh
bin/canon-mf42x --host 192.0.2.50 --id 7654321 --pin 7654321 login-check
```

Read E-Mail/I-Fax settings:

```sh
bin/canon-mf42x --host 192.0.2.50 --id "$CANON_ADMIN_ID" --pin "$CANON_ADMIN_PIN" \
  email-settings get --json
```

Set SMTP AUTH password while preserving current settings:

```sh
bin/canon-mf42x --host 192.0.2.50 --id "$CANON_ADMIN_ID" --pin "$CANON_ADMIN_PIN" \
  email-settings set \
  --smtp-auth 1 \
  --smtp-username noreply@example.com \
  --smtp-password "$CANON_SMTP_PASSWORD"
```

Set a full scan-to-email profile:

```sh
bin/canon-mf42x --host 192.0.2.50 --id "$CANON_ADMIN_ID" --pin "$CANON_ADMIN_PIN" \
  email-settings set \
  --smtp-server 192.0.2.10 \
  --email-address noreply@example.com \
  --smtp-auth 1 \
  --smtp-username noreply@example.com \
  --smtp-password "$CANON_SMTP_PASSWORD" \
  --smtp-tls 1 \
  --smtp-verify-certificate 0
```

## Perl API Example

```perl
use Canon::MF42x::RemoteUI;

my $canon = Canon::MF42x::RemoteUI->new(host => '192.0.2.50');

my $login = $canon->login_system_manager(
    id  => $ENV{CANON_ADMIN_ID},
    pin => $ENV{CANON_ADMIN_PIN},
);

die "login failed\n" unless $login->{ok};

my $settings = $canon->email_ifax_settings;
print "SMTP server: $settings->{smtp_server}\n";
```

## Language Compatibility

Canon Remote UI displays localized labels, but the HTML form structure uses numeric field names such as `i2032`, `i2140`, and `i2172`. This client maps those field names to English API names.

Confirmed with Russian Remote UI:

- Login endpoint: `/checkLogin.cgi`
- E-Mail/I-Fax edit page: `/tx_email_ifax_edit.html`
- E-Mail/I-Fax update endpoint: `/cgi/tx_email_ifax_edit.cgi`

## Safety Notes

- This tool can change live printer settings.
- Use `email-settings get` before `email-settings set`.
- Do not commit real printer PINs or SMTP passwords.
- Prefer environment variables or a local `.env` file excluded by `.gitignore`.

## License

MIT
