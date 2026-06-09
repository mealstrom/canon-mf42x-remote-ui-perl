package Canon::MF42x::RemoteUI;

use strict;
use warnings;

use Carp qw(croak);
use Encode qw(decode);
use HTTP::Tiny;
use URI::Escape qw(uri_escape_utf8);

our $VERSION = '0.3.0';

sub new {
    my ($class, %args) = @_;

    my $host = $args{host} || croak 'host is required';
    my $scheme = $args{scheme} || 'http';
    my $timeout = $args{timeout} || 15;

    $host =~ s{^https?://}{};
    $host =~ s{/+$}{};

    my $self = bless {
        host       => $host,
        scheme     => $scheme,
        base_url   => "$scheme://$host",
        timeout    => $timeout,
        cookies    => {},
        last_token => undef,
        http       => HTTP::Tiny->new(
            timeout         => $timeout,
            verify_SSL      => $args{verify_ssl} ? 1 : 0,
            default_headers => {
                'User-Agent' => 'Canon-MF42x-RemoteUI-Perl/' . $VERSION,
            },
        ),
    }, $class;

    return $self;
}

sub base_url {
    my ($self) = @_;
    return $self->{base_url};
}

sub get {
    my ($self, $path) = @_;
    return $self->_request('GET', $path);
}

sub post_form {
    my ($self, $path, $form) = @_;
    return $self->_request('POST', $path, $form);
}

sub login_system_manager {
    my ($self, %args) = @_;

    my $id  = defined $args{id}  ? $args{id}  : croak 'id is required';
    my $pin = defined $args{pin} ? $args{pin} : croak 'pin is required';

    my $res = $self->post_form('/checkLogin.cgi', {
        i0012  => 1,
        i0014  => $id,
        i0016  => $pin,
        errText => 'Error!',
    });

    my $location = $res->{headers}{location} || '';
    return {
        ok       => ($res->{status} == 302 && $location =~ m{/portal_top\.html\z}),
        status   => $res->{status},
        reason   => $res->{reason},
        location => $location,
    };
}

sub logout {
    my ($self) = @_;
    return $self->get('/logout.cgi');
}

sub detect_remote_ui_language {
    my ($self) = @_;

    my $res = $self->get('/');
    my $language = $self->{cookies}{language};

    if (!$language && defined $res->{content}) {
        if ($res->{content} =~ /Set-Cookie:\s*language=([^;]+)/i) {
            $language = $1;
        }
    }

    return {
        language => $language,
        status   => $res->{status},
    };
}

sub portal {
    my ($self) = @_;
    return $self->get('/portal_top.html');
}

sub email_ifax_settings {
    my ($self) = @_;
    my $settings = $self->_email_ifax_settings;
    delete $settings->{token};
    return $settings;
}

sub _email_ifax_settings {
    my ($self) = @_;

    my $res = $self->get('/tx_email_ifax_edit.html');
    _assert_success($res, 'failed to fetch E-Mail/I-Fax edit page');

    my $html = $res->{content};
    my $inputs = parse_inputs($html);

    return {
        token                       => $inputs->{iToken}{value},
        smtp_server                 => _value($inputs, 'i2032'),
        email_address               => _value($inputs, 'i2042'),
        pop_server                  => _value($inputs, 'i2052'),
        pop_username                => _value($inputs, 'i2062'),
        pop_password_change_enabled => _checked($inputs, 'i2070'),
        pop_rx                      => _checked($inputs, 'i2090'),
        pop_interval                => _value($inputs, 'i2102'),
        pop_before_smtp             => _checked($inputs, 'i2120'),
        apop                        => _checked($inputs, 'i2130'),
        smtp_auth                   => _checked($inputs, 'i2140'),
        smtp_username               => _value($inputs, 'i2152'),
        smtp_password_change_enabled => _checked($inputs, 'i2160'),
        smtp_tls                    => _checked($inputs, 'i2180'),
        smtp_verify_certificate     => _checked($inputs, 'i2190'),
        smtp_add_cn_to_verification => _checked($inputs, 'i2200'),
        pop_tls                     => _checked($inputs, 'i2210'),
        pop_verify_certificate      => _checked($inputs, 'i2220'),
        pop_add_cn_to_verification  => _checked($inputs, 'i2230'),
    };
}

sub set_email_ifax_settings {
    my ($self, %args) = @_;

    my $current = $self->_email_ifax_settings;
    my $token = $current->{token} || croak 'missing Canon form token';

    my %next = (%{$current}, %args);

    my %form = (
        iToken  => $token,
        i2032   => $next{smtp_server},
        i2042   => $next{email_address},
        i2052   => $next{pop_server},
        i2062   => $next{pop_username},
        i2090   => _bool($next{pop_rx}),
        i2102   => defined $next{pop_interval} ? $next{pop_interval} : 0,
        i2120   => _bool($next{pop_before_smtp}),
        i2130   => _bool($next{apop}),
        i2140   => _bool($next{smtp_auth}),
        i2152   => $next{smtp_username},
        i2180   => _bool($next{smtp_tls}),
        i2190   => _bool($next{smtp_verify_certificate}),
        i2200   => _bool($next{smtp_add_cn_to_verification}),
        i2210   => _bool($next{pop_tls}),
        i2220   => _bool($next{pop_verify_certificate}),
        i2230   => _bool($next{pop_add_cn_to_verification}),
        errText => 'Error!',
    );

    if (exists $args{pop_password}) {
        $form{i2070} = 1;
        $form{i2082} = $args{pop_password};
    }
    else {
        $form{i2070} = 0;
    }

    if (exists $args{smtp_password}) {
        $form{i2160} = 1;
        $form{i2172} = $args{smtp_password};
    }
    else {
        $form{i2160} = 0;
    }

    my $res = $self->post_form('/cgi/tx_email_ifax_edit.cgi', \%form);

    return {
        ok       => ($res->{status} == 302 || $res->{status} == 200),
        status   => $res->{status},
        reason   => $res->{reason},
        location => $res->{headers}{location},
    };
}

sub address_book_list {
    my ($self, %args) = @_;
    my $book = $args{book} || 'favorites';

    my $res = $self->get(_address_book_path($book));
    _assert_success($res, 'failed to fetch Address Book page');

    return parse_address_book($res->{content}, book => $book);
}

sub add_email_destination {
    my ($self, %args) = @_;

    my $book = $args{book} || 'favorites';
    my $name = defined $args{name} ? $args{name} : croak 'name is required';
    my $email = defined $args{email} ? $args{email} : croak 'email is required';
    my $slot = $args{slot};

    croak 'name must be 16 characters or fewer' if length($name) > 16;
    croak 'email must be 120 characters or fewer' if length($email) > 120;

    my $entries = $self->address_book_list(book => $book);
    if (!defined $slot) {
        my ($empty) = grep { !$_->{registered} } @{$entries};
        croak "no empty Address Book slot found in $book" unless $empty;
        $slot = $empty->{slot};
    }

    my ($entry) = grep { $_->{slot} == $slot } @{$entries};
    croak "slot $slot was not found in $book" unless $entry;
    croak "slot $slot is already registered" if $entry->{registered};

    my $list_html = $self->get(_address_book_path($book))->{content};
    my $list_token = _extract_token($list_html) || croak 'missing Address Book list token';

    my $open = $self->post_form(_address_book_open_endpoint($book), {
        iToken => $list_token,
        i2200  => $slot,
    });

    my $new_path = _location_path($open) || "/a_new.html?no=$slot";
    my $new_page = $self->get($new_path);
    _assert_success($new_page, 'failed to fetch Address Book destination type page');

    my $new_token = _extract_token($new_page->{content}) || croak 'missing destination type token';

    my $select = $self->post_form('/cgi/a_new.cgi', {
        no     => $slot,
        iToken => $new_token,
        i2011  => 2,       # E-Mail
        i2020  => $slot,
    });

    my $email_path = _location_path($select) || "/a_email_regist.html?no=$slot";
    my $email_page = $self->get($email_path);
    _assert_success($email_page, 'failed to fetch E-Mail destination form');

    my $email_token = _extract_token($email_page->{content}) || croak 'missing E-Mail destination token';

    my $save = $self->post_form('/cgi/a_email_regist.cgi', {
        no     => $slot,
        iToken => $email_token,
        i2012  => $slot,
        i2021  => $name,
        i2032  => $email,
    });

    return {
        ok       => ($save->{status} == 302 || $save->{status} == 200),
        status   => $save->{status},
        reason   => $save->{reason},
        location => $save->{headers}{location},
        book     => $book,
        slot     => $slot,
        name     => $name,
        email    => $email,
    };
}

sub delete_address_book_entry {
    my ($self, %args) = @_;

    my $book = $args{book} || 'favorites';
    my $slot = defined $args{slot} ? $args{slot} : croak 'slot is required';
    my $expected_name = $args{name};
    my $expected_destination = $args{destination};

    my $entries = $self->address_book_list(book => $book);
    my ($entry) = grep { $_->{slot} == $slot } @{$entries};
    croak "slot $slot was not found in $book" unless $entry;
    croak "slot $slot is not registered" unless $entry->{registered};

    if (defined $expected_name && $entry->{name} ne $expected_name) {
        croak "slot $slot name mismatch: expected '$expected_name', found '$entry->{name}'";
    }

    if (defined $expected_destination && $entry->{destination} ne $expected_destination) {
        croak "slot $slot destination mismatch: expected '$expected_destination', found '$entry->{destination}'";
    }

    my $list_html = $self->get(_address_book_path($book))->{content};
    my $list_token = _extract_token($list_html) || croak 'missing Address Book list token';

    my $delete = $self->post_form(_address_book_delete_endpoint($book), {
        iToken => $list_token,
        i2210  => $slot,
    });

    return {
        ok       => ($delete->{status} == 302 || $delete->{status} == 200),
        status   => $delete->{status},
        reason   => $delete->{reason},
        location => $delete->{headers}{location},
        book     => $book,
        slot     => $slot,
        name     => $entry->{name},
        type     => $entry->{type},
        destination => $entry->{destination},
    };
}

sub parse_inputs {
    my ($html) = @_;
    my %inputs;

    while ($html =~ /<input\b([^>]+)>/ig) {
        my $attrs = _parse_attrs($1);
        next unless defined $attrs->{name};

        my $name = $attrs->{name};
        my $type = lc($attrs->{type} || 'text');
        my $value = defined $attrs->{value} ? _html_unescape($attrs->{value}) : '';
        my $checked = exists $attrs->{checked} ? 1 : 0;

        if (exists $inputs{$name}) {
            if ($checked) {
                $inputs{$name} = {
                    type    => $type,
                    value   => $value,
                    checked => 1,
                };
            }
            next;
        }

        $inputs{$name} = {
            type    => $type,
            value   => $value,
            checked => $checked,
        };
    }

    return \%inputs;
}

sub parse_address_book {
    my ($html, %args) = @_;
    my $book = $args{book} || 'favorites';
    my @entries;

    while ($html =~ m{<tr>\s*(.*?)\s*</tr>}sig) {
        my $row = $1;
        next unless $row =~ /addressListLink\((\d+)\)/;
        my $slot = $1;

        my @cells = $row =~ m{<td[^>]*>(.*?)</td>}sig;
        next unless @cells >= 4;

        my $type_html = $cells[1];
        my $name = _strip_html($cells[2]);
        my $destination = _strip_html($cells[3]);
        my $registered = $row =~ /ButtonDisable|disabled=/i ? 0 : 1;
        my $type = 'unknown';

        if ($type_html =~ m{/media/ad_dot\.png}i) {
            $type = 'empty';
            $registered = 0;
        }
        elsif ($type_html =~ m{/media/ad_1\.png}i) {
            $type = 'email';
        }
        elsif ($type_html =~ m{/media/ad_2\.png}i) {
            $type = 'ifax';
        }
        elsif ($type_html =~ m{/media/ad_6\.png}i) {
            $type = 'file';
        }
        elsif ($type_html =~ m{/media/ad_grp\.png}i) {
            $type = 'group';
        }

        push @entries, {
            book        => $book,
            slot        => 0 + $slot,
            number      => sprintf('%02d', $slot),
            type        => $type,
            name        => $registered ? $name : '',
            destination => $destination,
            registered  => $registered ? 1 : 0,
        };
    }

    return \@entries;
}

sub _request {
    my ($self, $method, $path, $form) = @_;

    my $url = $path =~ m{^https?://} ? $path : $self->{base_url} . $path;
    my %headers;
    my $content;

    if (%{$self->{cookies}}) {
        $headers{Cookie} = join '; ', map { $_ . '=' . $self->{cookies}{$_} } sort keys %{$self->{cookies}};
    }

    if ($form) {
        $content = _form_encode($form);
        $headers{'Content-Type'} = 'application/x-www-form-urlencoded';
    }

    my $res = $self->{http}->request($method, $url, {
        headers => \%headers,
        content => $content,
    });

    if (defined $res->{content} && _content_is_utf8($res->{headers})) {
        $res->{content} = decode('UTF-8', $res->{content}, 1);
    }

    $self->_store_cookies($res->{headers});
    return $res;
}

sub _store_cookies {
    my ($self, $headers) = @_;

    my @values;
    if (exists $headers->{'set-cookie'}) {
        if (ref $headers->{'set-cookie'} eq 'ARRAY') {
            @values = @{$headers->{'set-cookie'}};
        }
        else {
            @values = ($headers->{'set-cookie'});
        }
    }

    for my $cookie (@values) {
        while ($cookie =~ /(?:^|,\s*)([A-Za-z0-9_]+)=([^;,]*)/g) {
            my ($name, $value) = ($1, $2);
            next if lc($name) =~ /^(path|expires|max-age|domain|secure|httponly)$/;
            $self->{cookies}{$name} = $value;
        }
    }
}

sub _form_encode {
    my ($form) = @_;

    my @pairs;
    for my $key (sort keys %{$form}) {
        my $value = defined $form->{$key} ? $form->{$key} : '';
        push @pairs, uri_escape_utf8($key) . '=' . uri_escape_utf8($value);
    }

    return join '&', @pairs;
}

sub _content_is_utf8 {
    my ($headers) = @_;
    my $content_type = $headers->{'content-type'} || '';
    return $content_type =~ /charset\s*=\s*utf-?8/i ? 1 : 0;
}

sub _parse_attrs {
    my ($raw) = @_;
    my %attrs;

    while ($raw =~ /([A-Za-z0-9_-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g) {
        my $key = $1;
        my $value = defined $2 ? $2 : defined $3 ? $3 : defined $4 ? $4 : 1;
        $attrs{$key} = $value;
    }

    return \%attrs;
}

sub _extract_token {
    my ($html) = @_;
    return $1 if $html =~ /name="iToken"\s+value="([0-9]+)"/;
    return $1 if $html =~ /value="([0-9]+)"\s+name="iToken"/;
    return undef;
}

sub _location_path {
    my ($res) = @_;
    my $location = $res->{headers}{location} || return undef;
    $location =~ s{^https?://[^/]+}{};
    return $location;
}

sub _address_book_path {
    my ($book) = @_;
    return '/a_addresslist.html'    if $book eq 'favorites';
    return '/a_addresslistcod.html' if $book eq 'coded';
    croak "unsupported Address Book: $book";
}

sub _address_book_open_endpoint {
    my ($book) = @_;
    return '/cgi/m_addresslist.cgi'    if $book eq 'favorites';
    return '/cgi/m_addresslistcod.cgi' if $book eq 'coded';
    croak "unsupported Address Book: $book";
}

sub _address_book_delete_endpoint {
    my ($book) = @_;
    return '/cgi/m_address_delete.cgi'    if $book eq 'favorites';
    return '/cgi/m_addresscod_delete.cgi' if $book eq 'coded';
    croak "unsupported Address Book: $book";
}

sub _strip_html {
    my ($html) = @_;
    $html =~ s/<script\b.*?<\/script>//sig;
    $html =~ s/<style\b.*?<\/style>//sig;
    $html =~ s/<[^>]+>//g;
    $html = _html_unescape($html);
    $html =~ s/^\s+|\s+\z//g;
    $html =~ s/\s+/ /g;
    return $html;
}

sub _html_unescape {
    my ($value) = @_;
    $value =~ s/&quot;/"/g;
    $value =~ s/&#39;/'/g;
    $value =~ s/&lt;/</g;
    $value =~ s/&gt;/>/g;
    $value =~ s/&amp;/&/g;
    return $value;
}

sub _value {
    my ($inputs, $name) = @_;
    return exists $inputs->{$name} ? $inputs->{$name}{value} : undef;
}

sub _checked {
    my ($inputs, $name) = @_;
    return exists $inputs->{$name} ? ($inputs->{$name}{checked} ? 1 : 0) : 0;
}

sub _bool {
    my ($value) = @_;
    return $value ? 1 : 0;
}

sub _assert_success {
    my ($res, $message) = @_;
    return if $res->{success};
    croak "$message: HTTP $res->{status} $res->{reason}";
}

1;

__END__

=head1 NAME

Canon::MF42x::RemoteUI - small Perl client for Canon MF42x Remote UI

=head1 DESCRIPTION

This module automates selected Canon MF42x Remote UI pages. It currently
supports System Manager login and E-Mail/I-Fax network settings.

=cut
