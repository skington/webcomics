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
        name          => 'Saturday Morning Breakfast Cereal',
        feed_url      => 'http://www.smbc-comics.com/rss.php',
        best_regexstr => {
            title => '^(?^x:(?<month_name> \w+? ))\ (?^x:(?<d> \d{1,2} ))\,\ '
                . '(?^x:(?<yyyy> \d{4} ))$',
            link => '^http\:\/\/www\.smbc\-comics\.com\/index\.php'
                . '\?db\=comics\&id\=(?<seq>\d+)$'
        },
    },
    {
        name          => 'Frankenstein Superstar',
        feed_url      => 'http://frankensteinsuperstar.com/feed/',
        best_regexstr => {
            link => '(?^x:(?<yyyy> \d{4} ))\/(?^x:(?<m> \d{1,2} ))'
                . '\/(?^x:(?<dd> \d{2} ))'
        },
    },
    {
        name          => 'Evil Inc.',
        feed_url      => 'http://www.evil-comic.com/index.xml',
        best_regexstr => {
            link => '^http\:\/\/www\.evil\-comic\.com\/archive\/'
                . '(?^x:(?<yyyy> \d{4} ))(?^x:(?<m> \d{1,2} ))'
                . '(?^x:(?<d> \d{1,2} ))\.html$',
            title => '^strip\ for\ (?^x:(?<month_name> \w+? ))\ \/\ '
                . '(?^x:(?<d> \d{1,2} ))\ \/\ (?^x:(?<yyyy> \d{4} ))$'
        },
    },
    {
        name          => 'The Non-Adventure of Wonderella',
        feed_url      => 'http://nonadventures.com/feed/',
        best_regexstr => {
            link => '(?^x:(?<yyyy> \d{4} ))\/(?^x:(?<m> \d{1,2} ))\/'
                . '(?^x:(?<dd> \d{2} ))'
        },
    },
    {
        name          => 'Reptilis Rex',
        feed_url      => 'http://www.reptilisrex.com/feed/',
        best_regexstr => {
            link => '(?^x:(?<yyyy> \d{4} ))\/(?^x:(?<m> \d{1,2} ))\/'
                . '(?^x:(?<dd> \d{2} ))'
        },
    },
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
    },
    {
        name          => 'Wayward Sons',
        feed_url      => 'http://waywardsons.keenspot.com/comic.rss',
        best_regexstr => {
            link => '^http\:\/\/waywardsons\.keenspot\.com\/d\/'
                . '(?^x:(?<yyyy> \d{4} ))(?^x:(?<m> \d{1,2} ))'
                . '(?^x:(?<d> \d{1,2} ))\.html$',
            title => '^Wayward\ Sons\ \-\ (?^x:(?<month_abbr> \w+? ))\ '
                . '(?^x:(?<d> \d{1,2} ))\,\ (?^x:(?<yyyy> \d{4} ))$',
        },
    },
    {
        name          => 'Dresden Codak',
        feed_url      => 'http://dresdencodak.com/feed/',
        best_regexstr => {
            link => '(?^x:(?<yyyy> \d{4} ))\/(?^x:(?<mm> \d{2} ))\/'
                . '(?^x:(?<dd> \d{2} ))'
        },
    },
    {
        name          => 'Lady Sabre & The Pirates of the Ineffable Aether',
        feed_url      => 'http://www.ineffableaether.com/feed/',
        best_regexstr => {
            link => '(?^x:(?<yyyy> \d{4} ))\/(?^x:(?<m> \d{1,2} ))\/'
                . '(?^x:(?<d> \d{1,2} ))'
        },
    },
    {
        name     => 'Basic Instructions',
        feed_url => 'http://basicinstructions.net/basic-instructions/rss.xml',
        best_regexstr => {
            link => '(?^x:(?<yyyy> \d{4} ))\/(?^x:(?<m> \d{1,2} ))\/'
                . '(?^x:(?<d> \d{1,2} ))',
        },
    },
    {
        name          => 'Sheldon',
        feed_url      => 'http://www.sheldoncomics.com/index.xml',
        best_regexstr => {
            link => '^http\:\/\/www\.sheldoncomics\.com\/archive\/'
                . '(?<seq>\d+)\.html$',
            title => '^strip\ for\ (?^x:(?<month_name> \w+? ))\ '
                . '\/\ (?^x:(?<d> \d{1,2} ))\ \/\ (?^x:(?<yyyy> \d{4} ))$'
        }
    },
    {
        name          => 'Cyanide & Happiness',
        feed_url      => 'http://feeds.feedburner.com/Explosm',
        best_regexstr => {
            link  => '^http\:\/\/www\.explosm\.net\/comics\/(?<seq>\d+)\/$',
            title => '^(?^x:(?<m> \d{1,2} ))\.(?^x:(?<d> \d{1,2} ))\.'
                . '(?^x:(?<yyyy> \d{4} ))$'
        },
    },
    # Help Desk has an RSS feed that shows the most recent entries, but
    # the titles are arbitrary and the URLs don't include the day of the
    # month. So it's not an error to expect no useful regexstrs.
    {
        name => 'Help Desk',
        feed_url => 'http://www.eviscerati.org/rss/rss.xml',
        best_regexstr => {
        },
    },
    {
        name          => 'xkcd',
        feed_url      => 'http://xkcd.com/rss.xml',
        best_regexstr => { link => '^http\:\/\/xkcd\.com\/(?<seq>\d+)\/$', },
    },
    {
        name          => 'Order of the Stick',
        feed_url      => 'http://www.giantitp.com/comics/oots.rss',
        best_regexstr => {
            link => '^http\:\/\/www\.GiantITP\.com\/comics\/'
                . 'oots(?<seq>\d{4})\.html$',
        }
    },
    {
        name          => 'Full Frontal Nerdity',
        feed_url      => 'http://ffn.nodwick.com/?feed=rss2',
        best_regexstr => {
            link  => '^http\:\/\/ffn\.nodwick\.com\/\?p\=(?<seq>\d+)$',
            title => '^(?^x:(?<m> \d{1,2} ))\/(?^x:(?<dd> \d{2} ))\/'
                . '(?^x:(?<yyyy> \d{4} ))$'
        },
    },
    {
        name     => 'You suck',
        feed_url => 'http://yousuckthecomic.com/index.xml',
        best_regexstr =>
            { link => '^http\:\/\/yousuckthecomic\.com\/go\/(?<seq>\d+)$' },
    },
    {
        name          => 'Scenes from a Multiverse',
        feed_url      => 'http://amultiverse.com/feed/',
        best_regexstr => {
            link => '(?^x:(?<yyyy> \d{4} ))\/(?^x:(?<m> \d{1,2} ))\/'
                . '(?^x:(?<dd> \d{2} ))'
        },
    },
    {
        name          => 'The Abominable Charles Christopher',
        feed_url      => 'http://www.abominable.cc/feed/',
        best_regexstr => {
            link => '(?^x:(?<yyyy> \d{4} ))\/(?^x:(?<m> \d{1,2} ))\/'
                . '(?^x:(?<dd> \d{2} ))'
        },
    },
    {
        name          => 'Misfile',
        feed_url      => 'http://www.misfile.com/rss.php',
        best_regexstr => {
            link => '^http\:\/\/www\.misfile\.com\/\?date\='
                . '(?^x:(?<yyyy> \d{4} ))\-(?^x:(?<m> \d{1,2} ))\-'
                . '(?^x:(?<d> \d{1,2} ))\#comic$',
            title => '^Comic\ Posted\:\ (?^x:(?<day_abbr> \w+? ))\,\ '
                . '(?^x:(?<d> \d{1,2} ))\ (?^x:(?<month_abbr> \w+? ))\ '
                . '(?^x:(?<yyyy> \d{4} ))$',
        },
    },
    {
        name          => 'Penny Arcade',
        feed_url      => 'http://feeds.penny-arcade.com/pa-mainsite',
        best_regexstr => {
            link => '(?^x:(?<yyyy> \d{4} ))\/(?^x:(?<m> \d{1,2} ))\/'
                . '(?^x:(?<d> \d{1,2} ))'
        },
    },
    {
        name          => 'PvP',
        feed_url      => 'http://www.pvponline.com/feed',
        best_regexstr => {
            link => '(?^x:(?<yyyy> \d{4} ))\/(?^x:(?<m> \d{1,2} ))\/'
                . '(?^x:(?<d> \d{1,2} ))'
        },
    },
    {
        name          => 'Partially Clips',
        feed_url      => 'http://partiallyclips.com/feed/atom/',
        best_regexstr => {
            link => '(?^x:(?<yyyy> \d{4} ))\/(?^x:(?<m> \d{1,2} ))\/'
                . '(?^x:(?<dd> \d{2} ))'
        },
    },
    {
        name          => 'Three Panel Soul',
        feed_url      => 'http://threepanelsoul.com/feed/atom/',
        best_regexstr => {
            link => '(?^x:(?<yyyy> \d{4} ))\/(?^x:(?<m> \d{1,2} ))\/'
                . '(?^x:(?<dd> \d{2} ))'
        },
    },
    {
        name          => 'Hark! A vagrant',
        feed_url      => 'http://www.rsspect.com/rss/vagrant.xml',
        best_regexstr => {
            link =>
                '^http\:\/\/www\.harkavagrant\.com\/index\.php\?id\=(?<seq>\d+)$',
        }
    },
    {
        name     => 'Perry Bible Fellowship',
        feed_url => 'http://pbfcomics.com/feed/feed.xml',
        best_regexstr =>
            { link => '^http\:\/\/pbfcomics\.com\/(?<seq>\d+)\/$', }
    },
    {
        name     => 'Wondermark',
        feed_url => 'http://feeds.feedburner.com/wondermark',
        best_regexstr =>
            { link => '^http\:\/\/wondermark\.com\/(?<seq>\d+)\/$', },
    },
);

if ($ENV{TEST_FEED}) {
    @feed_specs = grep { $_->{name} =~ /\Q$ENV{TEST_FEED}\E/i } @feed_specs;
}

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