package WWW::Webcomic::Entry;

use strict;
use warnings;
no warnings qw(uninitialized);
use vars qw($VERSION);
use English qw(-no_match_vars);

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::LazyRequire;
use WWW::Webcomic::MooseTypes;

=head1 NAME

WWW::Webcomic::Entry - an individual entry in a webcomic

=head1 DESCRIPTION

A Moose class representing an individual entry (typically a daily comic)
belonging to a webcomic.

=head2 Attributes

=over

=item title

The title of this entry. Can be blank or unhelpful (e.g. just the date,
with some random furniture like 'Comic for ...'). Not to be confused with
title text.

=cut

has 'title' => (
    is  => 'rw',
    isa => 'Str',
);

=item page

The page this entry refers to. A WWW::Webcomic::Page object.

=cut

has 'page' => (
    is            => 'rw',
    isa           => 'WWW::Webcomic::Page',
    lazy_required => 1,
);

=item date

The date this entry was originally posted. A DateTime object.

=cut

has 'date' => (
    is  => 'rw',
    isa => 'DateTime',
    predicate => 'has_date',
);

=back

=head2 Object methods

=over

=item link

A shortcut for $entry->page->url

=cut

sub link {
    my ($self) = @_;

    return $self->page->url;
}

=back

=head1 VERSION

This is version 0.02.

=cut

$VERSION = '0.02';

__PACKAGE__->meta->make_immutable;
1;