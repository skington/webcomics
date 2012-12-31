package WWW::Webcomic::Page::Feed;

use strict;
use vars qw($VERSION);
use English qw(-no_match_vars);

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::LazyRequire;
use WWW::Webcomic::MooseTypes;
extends 'WWW::Webcomic::Page';

use WWW::Webcomic::Entry;

use Carp;
use DateTime::Format::ISO8601;
use Text::Sequence;
use XML::Feed;

# Something in the list of modules above is turning these warnings on, so
# to be safe wait until everything's loaded before turning warnings on.
use warnings;
no warnings qw(uninitialized);

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
    my $feed;
    eval { $feed = XML::Feed->parse(\$contents) }
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

    # Grab all entries from the feed.
    my @entries = $self->_entries_from_feed_filtered_by_category;

    # Filter them by URL as well.
    @entries = $self->_entries_filtered_by_url(@entries);

    # Right, that's all we can do for now. Hope this is OK.
    return \@entries;
}

sub _entries_from_feed_filtered_by_category {
    my ($self) = @_;
    
    # Find out which categories these entries implement. If we find
    # out that we have e.g. Comics and Blog entries, we'll use that to
    # discard blog entries.
    my %has_category;
    for my $entry ($self->feed->entries) {
        for my $category ($entry->category) {
            $has_category{$category}++;
        }
    }
    my %skip_category = map { $_ => 1 }
        grep { /^ (?: blog | news ) $ /xi } keys %has_category;

    # Assemble entry summaries from the feed, skipping anything in the
    # dodgy categories we identified earlier.
    my @entries;
    feed_entry:
    for my $feed_entry ($self->feed->entries) {
        # Ignore entries if they're in an eminently skippable category.
        next feed_entry if grep { $skip_category{$_} } $feed_entry->category;

        # Looks initially good, so add this to the list.
        my $entry = $self->_entry_from_feed_entry($feed_entry);
        push @entries, $entry if $entry;
    }

    return @entries;
}

# Further stripping: strip anything that looks like a news post, or
# (if the URLs do this) isn't identified as being a comic.

sub _entries_filtered_by_url {
    my ($self, @entries)= @_;

    # Start with a strict regexp for matching 'comic' and then get
    # looser if that didn't help.
    my ($re_comic, $any_contain_comic);
    re:
    for my $re (qr{ /comic/ }x, qr/ \b comic \b /x) {
        $re_comic = $re;
        $any_contain_comic = grep { $_->page->url =~ $re_comic } @entries;
        last re if $any_contain_comic;
    }

    # Filter our entries.
    @entries = grep {
        !($_->page->url =~ m{ [/.] (?: forums | news ) [/.] }xi
            || ($any_contain_comic && $_->page->url !~ $re_comic));
    } @entries;

    return @entries;
}


sub _entry_from_feed_entry {
    my ($self, $feed_entry) = @_;

    # Build our entry; title is easy, and URL is fine but needs to be
    # sanitised for various tracking crud. If this failed, assume it's
    # a broken link which we can ignore.
    my $entry;
    eval {
        $entry = WWW::Webcomic::Entry->new(
            title => $feed_entry->title,
            page  => $self->page_with_same_options(
                $self->_sanitised_url($feed_entry->link),
            ),
        );
    } or do {
        carp "Couldn't create entry for " . $feed_entry->link;
        return;
    };

    # The date is normally straightforward, if we have one, but The Trenches
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

    return $entry;
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

=item best_regexstr

A hashref of type => regexstr, where type is one of C<title> or
C<link>, and regexstr is a regexstr (i.e. a regex in string form)
that best matches respectively the titles or URLs in the feed.
There may not be an entry for each type if the URL or titles
are arbitrary.

FIXME: say url rather than link.

=cut

has 'best_regexstr' => (
    is         => 'ro',
    isa        => 'HashRef',
    lazy_build => 1,
);

sub _build_best_regexstr {
    my ($self) = @_;

    my %best_regexstr;
    for my $field (qw(title link)) {
        my $regexstr = $self->_best_regexstr_for($field);
        $best_regexstr{$field} = $regexstr if defined $regexstr;
    }
    return \%best_regexstr;
}

sub _best_regexstr_for {
    my ($self, $field) = @_;

    # Find all our date-based regexstrs, and remember how much they
    # matched.
    my %total_match_length;
    for my $entry ($self->all_entries) {
        regexstr:
        for my $regexstr ($entry->regexstrs_date($field)) {
            # %+ doesn't last beyond the block it's in, it would appear,
            # which is why we don't just say %match_term = eval { ...; %+ }
            my %match_term;
            eval { $entry->$field =~ /$regexstr/; %match_term = %+; 1 }
                or next regexstr;

            # Right, remember how useful this regexstr was.
            for my $match (grep { defined $_ } values %match_term) {
                $total_match_length{$regexstr} += length($match);
            }
        }
    }

    # Look for sequences as well.
    if (my %sequence_match_length = $self->_sequence_regexstr($field)) {
        @total_match_length{keys %sequence_match_length}
            = values %sequence_match_length;
    }

    # The best regexstr is the one that matches the most - or, if there are
    # ties, the most complex one.
    my $regexstr_bestmatch = (
        sort {
            $total_match_length{$b} <=> $total_match_length{$a}
         || length($b) <=> length($a)
        } keys %total_match_length
    )[0];
    return if $total_match_length{$regexstr_bestmatch} == 0;

    ### TODO: write this data to entries, if we actually need to.
    ### Maybe our news feed pruning code is good enough that we don't
    ### need this any more?

    return $regexstr_bestmatch;
}

sub _sequence_regexstr {
    my ($self, $field) = @_;

    # Look for any numeric sequences in our entries.
    my @values = map { $_->$field } $self->all_entries;
    my ($sequences, $singletons) = Text::Sequence::find(@values);
    return if @$sequences == 0;

    # OK, remember how long they were - if they matched more than a
    # majority of the entries.
    my %sequence_regexstr_length;
    sequence:
    for my $sequence (@$sequences) {
        (my $regexstr = $sequence->re) =~ s/[(]/(?<seq>/;
        my ($length_match, $num_matches);
        for my $value (@values) {
            if (my ($match) = $value =~ /$regexstr/) {
                $length_match += length($match);
                $num_matches ++;
            }
        }
        next sequence if $num_matches < scalar @values / 2;
        $sequence_regexstr_length{$regexstr} = $length_match;
    }

    # And return this.
    return %sequence_regexstr_length;
}

=item regexstr_title

A regexstr that best matches the titles in this feed. May not exist
if the titles are arbitrary or blank.

=cut

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

