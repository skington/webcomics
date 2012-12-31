#!/usr/bin/env perl
# Check that we generate correct cache filenames from URLs.

use strict;
use warnings;
no warnings qw(uninitialized);

use lib::abs qw(../../../lib);
use Test::More;

use_ok('WWW::Webcomic::Page');

# We're not going to be caching anything, we're just testing that
# the files generated look sane, so this directory should be fine.
my $cache_directory = lib::abs::path('./');

my %expected_components = (
    'http://www.example.com/'        => ['www.example.com', 'Index page'],
    'http://www.example.com/foo'     => ['www.example.com', 'foo'],
    'http://www.example.com/foo/bar' => ['www.example.com', 'foo', 'bar'],
    'http://www.example.com/foo?q=search' =>
        ['www.example.com', 'foo?q=search'],
);
for my $url (sort keys %expected_components) {
    my $page = WWW::Webcomic::Page->new(
        url             => $url,
        cache_directory => $cache_directory
    );
    is_deeply(
        [$page->_cached_file_components($page->url)],
        $expected_components{$url},
        "Correct file components for $url"
    );
}

done_testing();