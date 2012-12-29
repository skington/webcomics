#!/usr/bin/env perl
# Filter out things that look like news posts, or are clearly not
# comic-related.

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

# Evil Inc. has links to forum posts.
# Misfile links to news posts.
# Penny Arcade has the word 'comic' in comic URLs.
my @feed_specs = (
    {
        name => 'Evil Inc.',
        url  => 'http://www.evil-comic.com/index.xml',
        test => sub { shift !~ /forum/ },
    },
    {
        name => 'Misfile',
        url  => 'http://www.misfile.com/rss.php',
        test => sub { shift !~ /news/ },
    },
    {
        name => 'Penny Arcade',
        url  => 'http://feeds.penny-arcade.com/pa-mainsite',
        test => sub { shift =~ m{/comic/} },
    }
);

for my $feed_spec (@feed_specs) {

    # Fetch the feed. We can parse it.
    my $feed = WWW::Webcomic::Page::Feed->new(
        url             => $feed_spec->{url},
        cache_directory => $cache_directory
    );
    ok($feed, "We can get the $feed_spec->{name} feed");
    my @entries = $feed->all_entries;
    ok(scalar @entries > 0, "We have entries in the $feed_spec->{name} feed");

    # All the entries look good.
    is(scalar(grep { !$feed_spec->{test}->($_->page->url) } @entries),
        0, "All entries in $feed_spec->{name} feed look correct");
}

# And we're done.
done_testing();