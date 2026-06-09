use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Canon::MF42x::RemoteUI',
    VERSION_FROM => 'lib/Canon/MF42x/RemoteUI.pm',
    ABSTRACT     => 'Perl client for Canon MF42x Remote UI',
    AUTHOR       => 'NORFOST contributors',
    EXE_FILES    => ['bin/canon-mf42x'],
    PREREQ_PM    => {
        'HTTP::Tiny'   => 0,
        'URI::Escape'  => 0,
        'JSON::PP'     => 0,
        'Getopt::Long' => 0,
        'Test::More'   => 0,
    },
    LICENSE => 'mit',
);
