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
    # necessarily keep them.
    my @feed_pages = $site->feed_pages;
    if (exists $site_details{$site_name}{feeds}) {
        ### TODO
    } else {
        is(scalar @feed_pages, 0, "$site_name has no feeds as expected");
    }
}

# And we're done.
done_testing();

sub site_details {
    ### TODO: Axe Cop
    my %site_details = (
        Doonesbury => { url => 'http://www.doonesbury.com/strip', },
        Dilbert    => { url => 'http://www.dilbert.com/', },
        SMBC       => { url => 'http://www.smbc-comics.com/', },
        Narbonic   => {
            url =>
                'http://www.webcomicsnation.com/shaenongarrity/narbonic_plus/series.php',
        },
        'Skin Horse' => { url => 'http://www.skin-horse.com/', },
        'Frankenstein Superstar' =>
            { url => 'http://frankensteinsuperstar.com/', },
        'Evil INC.'    => { url => 'http://www.evil-comic.com/index.html', },
        Wonderella     => { url => 'http://nonadventures.com/', },
        'Reptilis Rex' => { url => 'http://www.reptilisrex.com/', },
        'Girl Genius' =>
            { url => 'http://www.girlgeniusonline.com/comic.php', },
        'Dresden Codak' => { url => 'http://dresdencodak.com/', },
        '2D Goggles'    => { url => 'http://www.2dgoggles.com/', },
        'Basic Instructions' =>
            { url => 'http://www.basicinstructions.net/', },
        Sheldon               => { url => 'http://www.sheldoncomics.com/', },
        'Cyanide & Happiness' => { url => 'http://www.explosm.net/comics/', },
        Ubersoft          => { url => 'http://www.ubersoft.net/comic/hd/', },
        xkcd              => { url => 'http://xkcd.com/', },
        'Dinosaur comics' => { url => 'http://www.qwantz.com/', },
        'Order of the Stick' =>
            { url => 'http://giantitp.com/cgi-bin/GiantITP/ootscript', },
        'Full Frontal Nerdity' =>
            { url => 'http://ffn.nodwick.com/', },
        'Darths & Droids' =>
            { url => 'http://www.irregularwebcomic.net/darthsanddroids/', },
        'Least I Could Do' => { url => 'http://www.leasticoulddo.com/', },
        Oglaf              => { url => 'http://www.oglaf.com/', },
        'Scenes in a multiverse' => { url => 'http://amultiverse.com/', },
        Sinfest                  => { url => 'http://www.sinfest.net/', },
        'The Abominable Charles Christopher' =>
            { url => 'http://www.abominable.cc/', },
        Misfile => { url => 'http://www.misfile.com/', },
        'Gunnerkrigg Court' =>
            { url => 'http://www.gunnerkrigg.com/index2.php', },
        'Sister Claire' => { url => 'http://www.sisterclaire.com/', },
        'Something Positive' =>
            { url => 'http://www.somethingpositive.net/index.html', },
        'Scary-go-round'   => { url => 'http://www.scarygoround.com/', },
        'Penny Arcade'     => { url => 'http://www.penny-arcade.com/', },
        'The Trenches'     => { url => 'http://trenchescomic.com/', },
        'PvP'              => { url => 'http://www.pvponline.com/comic', },
        'Sluggy Freelance' => { url => 'http://www.sluggy.com/', },
        'El Goonish Shive' => { url => 'http://www.egscomics.com/', },
        'Spinnerette'      => { url => 'http://www.spinnyverse.com/', },
        'Afterlife Blues'  => { url => 'http://www.project-apollo.net/ab/', },
        'Partially Clips'  => { url => 'http://www.partiallyclips.com/', },
        'Hark! A Vagrant' =>
            { url => 'http://www.harkavagrant.com/index.php', },
        'Perry Bible Fellowship' => { url => 'http://pbfcomics.com/', },
        Wondermark               => { url => 'http://www.wondermark.com/', },
        'Three Panel Soul'       => { url => 'http://threepanelsoul.com/', },
        'Tragedy Series' => { url => 'http://tragedyseries.tumblr.com/', },
    );
    return %site_details;
}