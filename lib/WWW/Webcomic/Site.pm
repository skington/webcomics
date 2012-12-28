package WWW::Webcomic::Site;

use strict;
use warnings;
no warnings qw(uninitialized);
use vars qw($VERSION);
use English qw(-no_match_vars);

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::LazyRequire;

use WWW::Webcomic::Page;
use WWW::Webcomic::MooseTypes;

=head1 NAME

WWW::Webcomic::Site - a webcomic site object

=head1 SYNOPSIS

 my $site = WWW::Webcomic::Site->new(home_page => 'http://xkcd.com/');

=head1 DESCRIPTION

This is a Moose class that represents a webcomic site as a whole.

=head2 Attributes

=over

=item home_page

A WWW::Webcomic::Page object for the main page. If you supply a string
instead, a new WWW::Webcomic::Page object will be generated from that
string.

=cut

has 'home_page' => (
    is            => 'ro',
    isa           => 'WWW::Webcomic::Page',
    coerce        => 1,
    lazy_required => 1,
);

=back

=head1 VERSION

This is version 0.02.

=cut

$VERSION = '0.02';

__PACKAGE__->meta->make_immutable;
1;