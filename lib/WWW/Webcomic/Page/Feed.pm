package WWW::Webcomic::Page::Feed;

use strict;
use warnings;
no warnings qw(uninitialized);
use vars qw($VERSION);
use English qw(-no_match_vars);

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::LazyRequire;
use WWW::Webcomic::MooseTypes;
extends 'WWW::Webcomic::Page';

use XML::Feed;

=head1 NAME

WWW::Webcomic::Page::Feed - a page object for RSS / Atom feeds

=head1 DESCRIPTIOn

A subclass of WWW::Webcomic::Page which knows (a) how to parse RSS / Atom
feeds (by using XML::Feed), and (b) how to strip the cruft webcomics authors
chuck in their feeds.

=head2 Attributes

=over

=item feed

An XML::Feed object for the page in question. Lazily-constructed. Will die
with an error message if the feed contents are malformed.

=cut

has 'feed' => (
    is => 'ro',
    isa => 'XML::Feed',
    lazy_build => 1,
);

sub _build_feed {
    my ($self) = @_;

    my $contents = $self->contents;
    return if !$contents;
    my $feed = XML::Feed->parse(\$contents)
        or die "Couldn't parse feed at " . $self->url;
    return $feed;
}

=back

=head1 VERSION

This is version 0.02.

=cut

$VERSION = '0.02';

__PACKAGE__->meta->make_immutable;
1;

