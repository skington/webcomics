#!/usr/bin/env perl
# Get rid of stupid feedproxy etc. links within feeds

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

# Fetch the feed. We can parse it.
my $feed = WWW::Webcomic::Page::Feed->new(
    url             => 'http://www.smbc-comics.com/rss.php',
    cache_directory => $cache_directory
);
ok($feed, 'We can get the SMBC feed');
my @entries = $feed->all_entries;
ok(scalar @entries > 0, 'We have entries in the feed');

# None of the entries contain links to feedproxy.
is(scalar(grep { $_->page->url =~ /feedproxy/ } @entries),
    0, 'No links to feedproxy anywhere');

# And we're done.
done_testing();