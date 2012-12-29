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
check_redirected_website_is_cached();

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
    # Request a random number from a site that hopefully won't go AWOL
    # any time soon.
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

    # Fetch it; we get the same result.
    my $other_page = WWW::Webcomic::Page->new(
        url             => $url,
        cache_directory => $cache_directory
    );
    ok($other_page->contents, 'We can fetch that URL again');
    is($other_page->contents, $page->contents, 'It was cached');
}

sub check_redirected_website_is_cached {

    # First fetch the short link.
    my $short_url = 'http://bbc.co.uk/f1';
    my $short_link_page = WWW::Webcomic::Page->new(
        url             => $short_url,
        cache_directory => $cache_directory
    );
    ok($short_link_page->contents, q{We can fetch the BBC's F1 page});
    my $re_f1 = qr{Formula \s 1}x;
    like($short_link_page->contents, $re_f1,
        'It looks like a Formula 1 page');

    # We should expect a cached version of the long URL.
    my $long_url = 'http://www.bbc.co.uk/sport/0/formula1/';
    my $cached_file_path
        = $cache_directory . $long_url =~ s{http://(.+)/}{/$1/index.html}r;
    ok(-e $cached_file_path, 'We cached the resulting page');

    # OK, let's add some random gibberish to that file.
    ok(open(my $fh_cached, '>>', $cached_file_path),
        'We can write to the cached file');
    my $random_content = 'Not expecting this' . int(rand(1<<31));
    ok(print {$fh_cached} ($random_content), 'We can append to the cache');
    ok(close $fh_cached, 'Closing the file works');

    # Fetching the long URL gets us the expected content, both from the
    # original and our meddling.
    my $full_page = WWW::Webcomic::Page->new(
        url             => $long_url,
        cache_directory => $cache_directory
    );
    ok($full_page->contents, 'We can fetch the canonical URL of that page');
    like($full_page->contents, $re_f1, 'It still looks like an F1 page');
    like(
        $full_page->contents,
        qr{\Q$random_content\E},
        'Our random vandalism has taken'
    );

    # Fetching the short version again gets the same thing.
    my $short_link_page_again = WWW::Webcomic::Page->new(
        url             => $short_url,
        cache_directory => $cache_directory
    );
    ok($short_link_page_again->contents, 'We can fetch the short URL again');
    isnt($short_link_page_again->contents,
        $short_link_page->contents, 'Its contents have changed');
    is($short_link_page_again->contents,
        $full_page->contents, 'The two pages are now identical');
}

