use strict;
use warnings;

use Test::More;
use FindBin;
use lib "$FindBin::Bin/../lib";

use Canon::MF42x::RemoteUI;

my $html = <<'HTML';
<tr>
<td><a href="javascript:addressListLink(1)">01</a></td>
<td><a href="javascript:addressListLink(1)"><img src="/media/ad_1.png" alt="Электронная почта" /></a></td>
<td><a href="javascript:addressListLink(1)">Accounting</a></td>
<td>accounting@example.com</td>
<td><input class="ButtonEnable" type="button" value="Удалить" /></td>
</tr>
<tr>
<td><a href="javascript:addressListLink(7)">07</a></td>
<td><a href="javascript:addressListLink(7)"><img src="/media/ad_dot.png" alt="" /></a></td>
<td><a href="javascript:addressListLink(7)">Не зарегистрировано</a></td>
<td></td>
<td><input class="ButtonDisable" type="button" value="Удалить" disabled="disabled"/></td>
</tr>
HTML

my $rows = Canon::MF42x::RemoteUI::parse_address_book($html, book => 'favorites');

is scalar(@{$rows}), 2, 'two rows parsed';
is $rows->[0]{slot}, 1, 'slot parsed';
is $rows->[0]{number}, '01', 'number formatted';
is $rows->[0]{type}, 'email', 'email type parsed';
is $rows->[0]{name}, 'Accounting', 'name parsed';
is $rows->[0]{destination}, 'accounting@example.com', 'destination parsed';
is $rows->[0]{registered}, 1, 'registered row parsed';
is $rows->[1]{slot}, 7, 'empty slot parsed';
is $rows->[1]{type}, 'empty', 'empty type parsed';
is $rows->[1]{registered}, 0, 'empty row parsed';
is $rows->[1]{name}, '', 'empty name suppressed';

done_testing;
