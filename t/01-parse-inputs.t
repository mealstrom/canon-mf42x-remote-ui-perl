use strict;
use warnings;

use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use Canon::MF42x::RemoteUI;

my $html = <<'HTML';
<input type="hidden" name="iToken" value="6203620487" />
<input type="text" name="i2032" id="i2032" value="192.0.2.25" />
<input type="text" name="i2042" id="i2042" value="noreply@example.test" />
<input type="hidden" name="i2140" id="i2140A" value="0" />
<input type="checkbox" name="i2140" id="i2140B" value="1" checked='checked' />
<input type="hidden" name="i2190" id="i2190A" value="0" />
<input type="checkbox" name="i2190" id="i2190B" value="1" />
HTML

my $inputs = Canon::MF42x::RemoteUI::parse_inputs($html);

is $inputs->{iToken}{value}, '6203620487', 'token parsed';
is $inputs->{i2032}{value}, '192.0.2.25', 'smtp server parsed';
is $inputs->{i2042}{value}, 'noreply@example.test', 'email parsed';
is $inputs->{i2140}{value}, 1, 'checked checkbox value wins';
is $inputs->{i2140}{checked}, 1, 'checked checkbox parsed';
is $inputs->{i2190}{value}, 0, 'unchecked checkbox keeps hidden value';
is $inputs->{i2190}{checked}, 0, 'unchecked checkbox parsed';

done_testing;
