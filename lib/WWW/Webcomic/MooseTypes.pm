package WWW::Webcomic::MooseTypes;

use strict;
use warnings;
no warnings qw(uninitialized);
use vars qw($VERSION);
use English qw(-no_match_vars);

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::LazyRequire;

=head1 NAME

WWW::Webcomic::MooseTypes - various Moose types used by WWW::Webcomic::*

=head1 DESCRIPTION

Internal use only.

=cut

class_type 'URI', { class => 'URI' };
coerce 'URI', from 'Str', via {
    URI->new($_);
};

class_type 'WWW::Webcomic::Page', { class => 'WWW::Webcomic::Page' };
### TODO: test this, and document it.
coerce 'WWW::Webcomic::Page', from 'URI', via {
    WWW::Webcomic::Page->new(url => $_);
};
coerce 'WWW::Webcomic::Page', from 'Str', via {
    WWW::Webcomic::Page->new(url => $_);
};

### TODO: test that this does indeed fail if the directory doesn't exist,
### or isn't writable etc.
subtype 'WWW::Webcomic::CacheDir', as 'Str', where {
    -d $_ && -r _ && -w _
};

$VERSION = '0.02';

__PACKAGE__->meta->make_immutable;
1;