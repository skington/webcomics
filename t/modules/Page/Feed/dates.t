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

# Two feeds here.
# Wonderella has perfectly fine dates; The Trenches does not.
my %feed_url = (
    'Wonderella'   => 'http://nonadventures.com/feed/',
    'The Trenches' => 'http://trenchescomic.com/feed',
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

    # All of the entries have dates, and they're different.
    my %found_date;
    entry:
    for my $entry (@entries) {
        ok($entry->has_date,
            'Entry for ' . $entry->page->url . ' has a date')
            or next entry;
        my $datetime = $entry->date->ymd . ' ' . $entry->date->hms;
        ok(!$found_date{$datetime}++,
            "Haven't seen datetime $datetime before");
    }
}

# And we're done.
done_testing();