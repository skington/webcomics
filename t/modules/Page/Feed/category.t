#!/usr/bin/env perl
# Strip entries from feeds if they're in an obvious news or blog category.

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
    url             => 'http://frankensteinsuperstar.com/feed/',
    cache_directory => $cache_directory
);
ok($feed, 'We can get the Frankenstein Superstar feed');
my @entries = $feed->all_entries;
ok(scalar @entries > 0, 'We have entries in the feed');

# None of the entries contain blog posts
is(scalar(grep { $_->page->url =~ /blog/ } @entries),
    0, 'No blog posts');

# And we're done.
done_testing();