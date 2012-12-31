#!/usr/bin/env perl
# Work out the best regexstr for given feeds.

use strict;
use warnings;
no warnings qw(uninitialized);

use lib::abs qw(../../../../lib ../../../lib);
use Test::More;
use Utils qw(_directory_is_safe);

# Expect to find a cached version of the RSS feeds in our fixtures directory,
# but be ready to repopulate it if necessary.
use_ok('WWW::Webcomic::Page::Feed');
my $cache_directory = lib::abs::path('fixtures');
Utils::_directory_is_safe($cache_directory, 'fixture directory');

# Expected regexstrs for various websites. This list will get long, as it's
# the main way of testing RSS feeds.
my @feed_specs = (
    {
        name          => 'Girl Genius',
        feed_url      => 'http://www.girlgeniusonline.com/ggmain.rss',
        best_regexstr => {
            link => '^http\:\/\/www\.girlgeniusonline\.com\/comic\.php\?'
                . 'date\=(?^x:(?<yyyy> \d{4} ))(?^x:(?<m> \d{1,2} ))'
                . '(?^x:(?<d> \d{1,2} ))$',
            title => '^Girl\ Genius\ for\ (?^x:(?<day_name> \w+? ))\,\ '
                . '(?^x:(?<month_name> \w+? ))\ (?^x:(?<d> \d{1,2} ))\,\ '
                . '(?^x:(?<yyyy> \d{4} ))$'
        },
    }
);

for my $feed_spec (@feed_specs) {

    # Fetch the feed. We can parse it.
    my $feed = WWW::Webcomic::Page::Feed->new(
        url             => $feed_spec->{feed_url},
        cache_directory => $cache_directory
    );
    ok($feed, "We can get the $feed_spec->{name} feed");
    my @entries = $feed->all_entries;
    ok(scalar @entries > 0, "We have entries in the $feed_spec->{name} feed");

    # The regexstr hashref is what we expect.
    my $best_regexstr = $feed->best_regexstr;
    is_deeply(
        $best_regexstr,
        $feed_spec->{best_regexstr},
        "The regexstrs for $feed_spec->{name} are what we expect"
    ) or diag(
        "Got:\n",
        "Title: $best_regexstr->{title}\n",
        "Link: $best_regexstr->{link}\n",
        "\nExpected:\n",
        "Title: $feed_spec->{best_regexstr}->{title}\n",
        "Link: $feed_spec->{best_regexstr}->{link}\n"
    );
}

# And we're done.
done_testing();