#!/usr/bin/env perl
# Get rid of stupid utm_source etc. rubbish from links within feeds

use strict;
use warnings;
no warnings qw(uninitialized);

use lib::abs qw(../../../../lib ../../../lib);
use Test::More;
use Utils qw(_directory_is_safe);

# Expect to find a cached version of the RSS feed in our fixtures directory,
# but be ready to repopulate it if necessary.
use_ok('WWW::Webcomic::Page::Feed');
my $cache_directory = lib::abs::path('fixtures');
Utils::_directory_is_safe($cache_directory, 'fixture directory');

# Two feeds here: Partially Clips has utm_bullshit directly, while
# SMBC has utm_wankery indirectly via the feedproxy links.
my %feed_url = (
    'Partially Clips' => 'http://partiallyclips.com/feed/atom/',
    'SMBC'            => 'http://www.smbc-comics.com/rss.php',
);

for my $feed_name (sort keys %feed_url) {

    # Fetch the feed. We can parse it.
    my $feed = WWW::Webcomic::Page::Feed->new(
        url             => $feed_url{$feed_name},
        cache_directory => $cache_directory
    );
    ok($feed, "We can get the $feed_name feed");
    my @entries = $feed->all_entries;
    ok(scalar @entries > 0, "We have entries in the $feed_name feed");

    # None of the entries contain utm_source, utm_medium or utm_campaign
    for my $keyword (qw(source medium campaign)) {
        is(scalar(grep { $_->page->url =~ /utm_$keyword/ } @entries),
            0, "No mention of utm_$keyword anywhere in $feed_name feed");
    }
}

# And we're done.
done_testing();