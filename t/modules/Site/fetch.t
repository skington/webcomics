#!/usr/bin/env perl
# Make sure we can fetch our sites from the Internet.

use strict;
use warnings;
no warnings qw(uninitialized);

use lib::abs qw(../../../lib ../../lib);
use Utils qw(_directory_is_safe);

use Test::More;

use_ok('WWW::Webcomic::Site');

my %site_details = site_details();

# Make sure we have a cache directory. This directory shouldn't normally be
# cleared out, but let's be ready for it being empty and re-populating it.
my $cache_directory = lib::abs::path('./cache');
_directory_is_safe($cache_directory);

# Check each site for basics.
for my $site_name (sort keys %site_details) {

    # Create a Site object. Explcitly pass a Page object so we can
    # specify a cache.
    my $site = WWW::Webcomic::Site->new(
        home_page => WWW::Webcomic::Page->new(
            url             => $site_details{$site_name}{url},
            cache_directory => $cache_directory
        )
    );

    # Make sure the home page is fine.
    ok($site, "We have a Site object for $site_name");
    my $page_name = "${site_name}'s home page";
    ok($site->home_page,           "We have a Page object for $page_name");
    ok($site->home_page->contents, "We have page contents for $page_name");

    # Find the raw feeds. Some of these will be unhelpful, so we won't
    # necessarily keep them, but we should expect e.g. RDF, RSS and Atom
    # for the keenest of sites.
    my @feed_pages = $site->all_feed_pages;
    if (exists $site_details{$site_name}{feeds}) {
        is_deeply(
            [sort map { $_->url } @feed_pages],
            [sort @{ $site_details{$site_name}{feeds} }],
            "$site_name has the feeds we expect"
            )
            or diag("Expected feeds:\n"
                . join("\n", @{ $site_details{$site_name}{feeds} })
                . "\nGot\n"
                . join("\n", map { $_->url } @feed_pages));
    } elsif (exists $site_details{$site_name}{feed_url}) {
        if(is(scalar @feed_pages, 1, "$site_name has only one feed")) {
            is(
                $feed_pages[0]->url,
                $site_details{$site_name}{feed_url},
                "$site_name has the feed URL we expected"
            );
        } else {
            diag(
                "Found multiple feeds for $site_name:\n",
                join("\n", map { $_->url->as_string } @feed_pages)
            );
        }
    } else {
        is(scalar @feed_pages, 0, "$site_name has no feeds as expected")
            or diag("Found the following feeds:\n",
            join("\n",
                map { $_->url->as_string } @feed_pages));
    }
}

# And we're done.
done_testing();

sub site_details {
    ### TODO: Axe Cop
    my %site_details = (

        # Doonesbury has the standard Slate RSS feed, which doesn't actually
        # include any Doonesbury strips.
        Doonesbury => {
            url      => 'http://www.doonesbury.com/strip',
            feed_url => 'http://slate.com/rss'
        },
        Dilbert => { url => 'http://www.dilbert.com/', },
        SMBC    => {
            url      => 'http://www.smbc-comics.com/',
            feed_url => 'http://www.smbc-comics.com/rss.php'
        },

        # Two feeds for Narbonic: a Narbonic feed and a Shaenon Garrity feed.
        Narbonic => {
            url =>
                'http://www.webcomicsnation.com/shaenongarrity/narbonic_plus/series.php',
            feeds => [
                'http://www.webcomicsnation.com/rss.php?type=creator&creator=14',
                'http://www.webcomicsnation.com/rss.php?type=series&series=1914'
            ],
        },
        'Skin Horse' => {
            url      => 'http://www.skin-horse.com/',
            feed_url => 'http://skin-horse.com/feed/'
        },
        'Frankenstein Superstar' => {
            url      => 'http://frankensteinsuperstar.com/',
            feed_url => 'http://frankensteinsuperstar.com/feed/'
        },
        'Evil INC.' => {
            url      => 'http://www.evil-comic.com/index.html',
            feed_url => 'http://www.evil-comic.com/index.xml'
        },
        Wonderella => {
            url      => 'http://nonadventures.com/',
            feed_url => 'http://nonadventures.com/feed/'
        },
        'Reptilis Rex' => {
            url      => 'http://www.reptilisrex.com/',
            feed_url => 'http://www.reptilisrex.com/feed/'
        },
        'Girl Genius' => {
            url      => 'http://www.girlgeniusonline.com/comic.php',
            feed_url => 'http://www.girlgeniusonline.com/ggmain.rss'
        },
        'Dresden Codak' => {
            url      => 'http://dresdencodak.com/',
            feed_url => 'http://dresdencodak.com/feed/'
        },
        '2D Goggles' => {
            url      => 'http://www.2dgoggles.com/',
            feed_url => 'http://sydneypadua.com/2dgoggles/feed/'
        },
        'Basic Instructions' => {
            url   => 'http://www.basicinstructions.net/',
            feeds => [
                'http://basicinstructions.net/basic-instructions/atom.xml',
                'http://basicinstructions.net/basic-instructions/rss.xml',
                'http://basicinstructions.net/basic-instructions/rdf.xml'
            ],
        },
        Sheldon => {
            url      => 'http://www.sheldoncomics.com/',
            feed_url => 'http://www.sheldoncomics.com/index.xml'
        },
        'Cyanide & Happiness' => {
            url      => 'http://www.explosm.net/comics/',
            feed_url => 'http://feeds.feedburner.com/Explosm'
        },
        Ubersoft => {
            url      => 'http://www.ubersoft.net/comic/hd/',
            feed_url => 'http://www.eviscerati.org/rss/rss.xml'
        },
        xkcd => {
            url      => 'http://xkcd.com/',
            feed_url => 'http://xkcd.com/rss.xml'
        },
        'Dinosaur comics'    => { url => 'http://www.qwantz.com/', },
        'Order of the Stick' => {
            url      => 'http://giantitp.com/cgi-bin/GiantITP/ootscript',
            feed_url => 'http://www.giantitp.com/comics/oots.rss'
        },
        'Full Frontal Nerdity' => {
            url      => 'http://ffn.nodwick.com/',
            feed_url => 'http://ffn.nodwick.com/?feed=rss2'
        },

        # These feeds are also useless; they're the irregular webcomic
        # feeds.
        'Darths & Droids' => {
            url   => 'http://www.irregularwebcomic.net/darthsanddroids/',
            feeds => [
                'http://www.irregularwebcomic.net/rss.xml',
                'http://www.irregularwebcomic.net/rss2.xml',
            ]
        },
        'Least I Could Do' => { url => 'http://www.leasticoulddo.com/', },
        Oglaf              => { url => 'http://www.oglaf.com/', },
        'Scenes in a multiverse' => {
            url      => 'http://amultiverse.com/',
            feed_url => 'http://amultiverse.com/feed/'
        },
        Sinfest => { url => 'http://www.sinfest.net/', },
        'The Abominable Charles Christopher' => {
            url      => 'http://www.abominable.cc/',
            feed_url => 'http://www.abominable.cc/feed/'
        },
        Misfile => {
            url      => 'http://www.misfile.com/',
            feed_url => 'http://www.misfile.com/rss.php'
        },
        'Gunnerkrigg Court' => {
            url      => 'http://www.gunnerkrigg.com/index2.php',
            feed_url => 'http://www.rsspect.com/rss/gunner.xml'
        },
        'Sister Claire' => { url => 'http://www.sisterclaire.com/', },

        ### FIXME: Something Positive's feed is for some reason a single
        ### guest post he did for Questionable Content.
        'Something Positive' =>
            { url => 'http://www.somethingpositive.net/index.html' },
        'Scary-go-round' => {
            url      => 'http://www.scarygoround.com/',
            feed_url => 'http://badmachinery.com/index.xml'
        },
        'Penny Arcade' => {
            url      => 'http://www.penny-arcade.com/',
            feed_url => 'http://feeds.penny-arcade.com/pa-mainsite'
        },
        'The Trenches' => {
            url      => 'http://trenchescomic.com/',
            feed_url => 'http://trenchescomic.com/feed'
        },
        'PvP' => {
            url      => 'http://www.pvponline.com/comic',
            feed_url => 'http://www.pvponline.com/feed'
        },

        ### FIXME: Sluggy Freelance's feed contains only the most recent entry
        ### rather than being useful as a feed.
        'Sluggy Freelance' => { url => 'http://www.sluggy.com/', },
        'El Goonish Shive' => { url => 'http://www.egscomics.com/', },
        'Spinnerette'      => {
            url      => 'http://www.spinnyverse.com/',
            feed_url => 'http://www.spinnyverse.com/feed/'
        },

        'Afterlife Blues' => {
            url      => 'http://www.project-apollo.net/ab/',
            feed_url => 'http://project-apollo.net/ab/ab-rss.xml'
        },
        'Partially Clips' => {
            url      => 'http://www.partiallyclips.com/',
            feed_url => 'http://partiallyclips.com/feed/atom/'
        },
        'Hark! A Vagrant' => {
            url      => 'http://www.harkavagrant.com/index.php',
            feed_url => 'http://www.rsspect.com/rss/vagrant.xml'
        },
        'Perry Bible Fellowship' => {
            url      => 'http://pbfcomics.com/',
            feed_url => 'http://pbfcomics.com/feed/feed.xml'
        },
        Wondermark => {
            url      => 'http://www.wondermark.com/',
            feed_url => 'http://feeds.feedburner.com/wondermark'
        },
        'Three Panel Soul' => {
            url      => 'http://threepanelsoul.com/',
            feed_url => 'http://threepanelsoul.com/feed/atom/'
        },
        'Tragedy Series' => {
            url      => 'http://tragedyseries.tumblr.com/',
            feed_url => 'http://tragedyseries.tumblr.com/rss'
        },
    );
    return %site_details;
}