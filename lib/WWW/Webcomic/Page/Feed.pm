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

use DateTime::Format::ISO8601;
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

    my @entries;
    for my $feed_entry ($self->feed->entries) {
        # Build our entry; title is easy, and URL is fine but needs to be
        # sanitised for various tracking crud.
        my $entry = WWW::Webcomic::Entry->new(
            title => $feed_entry->title,
            page  => $self->page_with_same_options(
                $self->_sanitised_url($feed_entry->link),
            ),
        );

        # The date is normally straightforward, but The Trenches
        # decides to do things differently.
        my $date = $feed_entry->issued;
        if (!$date && $feed_entry->{entry}{pubDate}) {
            my $date_iso8601 = eval {
                DateTime::Format::ISO8601->parse_datetime(
                    $feed_entry->{entry}{pubDate});
            };
            $date = $date_iso8601 if $date_iso8601;
        }
        if ($date) {
            $entry->date($date);
        }

        # OK, that looks good enough.
        push @entries, $entry;
    }

    return \@entries;
}

sub _sanitised_url {
    my ($self, $url) = @_;

    # If the URL looks like a redirect by a hosted feed site,
    # fetch it and track any redirects.
    if ($url =~ / (?: feedproxy | feeds ) [.] /x) {
        my $proxy_page = $self->page_with_same_options($url);
        $proxy_page->contents;
        $url = $proxy_page->canonical_url;
    }

    # Remove stupid tracking nonsense from URLs.
    for my $keyword (qw(source medium campaign)) {
        $url =~ s{
            ([?&])
            utm_$keyword = [^&]+
            (?: & | $)
        }{$1}x;
    }
    $url =~ s/[?&]$//;

    # And we're done.
    return $url;
}

=back

=head2 Object methods

=over

=item page_with_same_options

 In: $url (URI object or URL string)
 Out: $page (WWW::Webcomic::Page object)

Supplied with a URL suitable to be passed to the constructor of
WWW::Webcomic::Page, returns a WWW::Webcomic::Page object similar to
this WWW::Webcomic::Feed object.

At the moment, 'similar' means 'with the same cache_directory attribute
value'.

=cut

sub page_with_same_options {
    my ($self, $url) = @_;

    my %page_constructor_args;
    if ($self->has_cache_directory) {
        $page_constructor_args{cache_directory} = $self->cache_directory;
    }

    return WWW::Webcomic::Page->new(url => $url, %page_constructor_args);
}

=back

=head1 VERSION

This is version 0.02.

=cut

$VERSION = '0.02';

__PACKAGE__->meta->make_immutable;
1;

