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

use WWW::Webcomic::Entry;

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
    is         => 'ro',
    isa        => 'XML::Feed',
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

=item entries

An arrayref of WWW::Webcomic::Entry objects derived from the feed.
(Use the method all_entries to get a list.)

=cut

has 'entries' => (
    is         => 'ro',
    isa        => 'ArrayRef[WWW::Webcomic::Entry]',
    lazy_build => 1,
    traits     => ['Array'],
    handles    => { all_entries => 'elements', },
);

sub _build_entries {
    my ($self) = @_;

    # Remember to pass along our cache_directory setting if we have one.
    my %page_constructor_args;
    if ($self->has_cache_directory) {
        $page_constructor_args{cache_directory} = $self->cache_directory;
    }

    # Go through the feed generating Entry objects.
    my @entries;
    for my $feed_entry ($self->feed->entries) {
        my $entry = WWW::Webcomic::Entry->new(
            title => $feed_entry->title,
            page  => WWW::Webcomic::Page->new(
                url => $feed_entry->link,
                %page_constructor_args
            ),
        );
        $entry->date($feed_entry->issued) if $feed_entry->issued;
        push @entries, $entry;
    }

    return \@entries;
}

=back

=head1 VERSION

This is version 0.02.

=cut

$VERSION = '0.02';

__PACKAGE__->meta->make_immutable;
1;

