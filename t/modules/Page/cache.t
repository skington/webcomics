#!/usr/bin/env perl
# Check that we cache pages.

use strict;
use warnings;
no warnings qw(uninitialized);

use lib::abs qw(../../../lib ../../lib);
use Utils qw(_directory_is_safe);

use Test::More;

use_ok('WWW::Webcomic::Page');

# Make sure our cache directory is safe.
my $cache_directory = lib::abs::path('cache');
_directory_is_safe($cache_directory, 'Cache directory');

# Make sure we can retrieve a cached file we wrote ourselves.
read_prepared_directory();
read_prepared_file();

# And now make sure that any page fetched from the wild is cached as well.
check_website_is_cached();

# Clear the cache.
### TODO: Windows
is(system('/bin/rm', '-fr', $cache_directory), 0, 'Cache directory deleted');

# And we're done.
done_testing();

sub read_prepared_directory {

    # Build a fake website for example.com. This should never work in a live
    # system, so it's only if we've implemented caching that we know that it
    # worked.
    # Start off with a directory entry, ending with a slash. The leafname
    # will be index.html, arbitrarily.
    _directory_is_safe("$cache_directory/example.com", 'example.com website');
    my $cached_file_path = "$cache_directory/example.com/index.html";
    _write_cached_file($cached_file_path, <<RAW_HTML);
<html><head><title>example.com</title></head>
<body><p>Lorem
ipsum and other
nonsense words</p>
</body>
</html>
RAW_HTML

    # Right, "fetch" that page from the cache.
    my $page = WWW::Webcomic::Page->new(
        url             => 'http://example.com/',
        cache_directory => $cache_directory,
    );
    ok($page->contents, 'Our cached bogus website has contents');
    like($page->contents, qr{Lorem}, 'Lorem found in contents');
    like(
        $page->tree->look_down(_tag => 'p')->content_array_ref->[0],
        qr{Lorem \s+ ipsum}xsm,
        q{There's lorem ipsum in there}
    );
}

sub read_prepared_file {

    # As above, but using a URL that does not end with a slash, so
    # no adding index.html here.
    _directory_is_safe("$cache_directory/example.com");
    _directory_is_safe("$cache_directory/example.com/foo");
    _directory_is_safe("$cache_directory/example.com/foo/bar");
    my $cached_file_path = "$cache_directory/example.com/foo/bar/baz";
    _write_cached_file($cached_file_path, <<RAW_HTML);
<html><head></head>
<body>
<div><span>There's no reason for this</span></div>
</body>
</html>
RAW_HTML

    my $page = WWW::Webcomic::Page->new(
        url             => 'http://example.com/foo/bar/baz',
        cache_directory => $cache_directory
    );
    ok($page->contents, 'Our cached bogus website file has contents');
    like($page->contents, qr{reason}, 'reason found in contents');
    like(
        $page->tree->look_down(_tag => 'div')->look_down(_tag => 'span')
            ->content_array_ref->[0],
        qr{no \s reason \s for \s this}xsm,
        'Div and span tags found',
    );
}

sub _write_cached_file {
    my ($cached_file_path, $contents) = @_;

    ok(open(my $fh, '>', $cached_file_path),
        'We can write to the index file');
    ok((print {$fh} $contents), 'We can write our prepared contents');
    ok(close $fh, 'Written out correctly');
    ok(-e $cached_file_path, 'The cached file exists');
    ok(-s $cached_file_path > 50 && -s _ < 1000,
        'It looks like it has the right sort of size');
}

sub check_website_is_cached {
    my $url = 'http://www.random.org/integers/?num=1&min=1&max=100000'
        . '&col=1&base=10&format=plain&rnd=new';
    my $page = WWW::Webcomic::Page->new(
        url => $url,
        cache_directory => $cache_directory,
    );
    ok($page->contents, 'We could fetch a random number from random.org');
    like(
        $page->contents,
        qr{ ^ \d{1,6} $ }x,
        q{It's a 1-6 digit random number}
    );

    my $other_page = WWW::Webcomic::Page->new(
        url             => $url,
        cache_directory => $cache_directory
    );
    ok($other_page->contents, 'We can fetch that URL again');
    is($other_page->contents, $page->contents, 'It was cached');
}

