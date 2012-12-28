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
use WWW::Webcomic::Page::Feed;
use WWW::Webcomic::MooseTypes;

use Carp;
use Feed::Find;
use XML::Feed;

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
    is       => 'ro',
    isa      => 'WWW::Webcomic::Page',
    coerce   => 1,
    required => 1,
);

=item feed_pages

An arrayref of RSS or Atom feed pages served by this site. WWW::Webcomic::Page
objects - so not parsed or anything.

=cut

has 'feed_pages' => (
    is         => 'rw',
    isa        => 'ArrayRef[WWW::Webcomic::Page::Feed]',
    lazy_build => 1,
    traits     => ['Array'],
    handles    => { all_feed_pages => 'elements', },
);

sub _build_feed_pages {
    my ($self) = @_;

    # Find whether we have any RSS or Atom feeds linked from the home page.
    # If there's nothing there, fine.
    # home_page is ro and required, so we know it exists at this point.
    my $homepage_contents = $self->home_page->contents;
    my @feed_urls = Feed::Find->find_in_html(\$homepage_contents,
        $self->home_page->url);
    return [] if !@feed_urls;

    # Right, fetch the feeds. Get them via our Feed module (a) so we can
    # cache this stuff, and (b) so we can override the default user-agent.    
    # webcomicsnation.com and possibly others decide to brush you off
    # if you use the default libwww/perl user agent.
    my @feeds;
    for my $feed_url (@feed_urls) {
        my $feed_page = WWW::Webcomic::Page::Feed->new(url => $feed_url);
        if ($self->home_page->cache_directory) {
            $feed_page->cache_directory($self->home_page->cache_directory)
        }
        eval { $feed_page->contents } and push @feeds, $feed_page;
    }

    return \@feeds;
}

=back

=head1 VERSION

This is version 0.02.

=cut

$VERSION = '0.02';

__PACKAGE__->meta->make_immutable;
1;