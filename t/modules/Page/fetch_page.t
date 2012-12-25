#!/usr/bin/env perl
# Make sure we can fetch pages from the Internet. This is mostly a test
# of our Moose wrapper.

use strict;
use warnings;
no warnings qw(uninitialized);

use lib::abs qw(../../../lib);
use Test::More;

use_ok('WWW::Webcomic::Page');

# Simple test first off: load Google's home page.
# The requirement is that we shold be damn well sure that the page exists
# and is happy to be hammered; we don't need this to be a webcomic page
# at this point.
my $page = WWW::Webcomic::Page->new(url => 'http://www.google.com');
isa_ok($page, 'WWW::Webcomic::Page', 'Google is a valid page to fetch');

# Fetch the page. We should have something that looks googlish.
my $page_contents = $page->fetch_page;
ok($page_contents, 'We got something from fetch_page');
like($page_contents, qr{.* < \s* html [^>]* > }xsm, 'Looks like HTML');

# And we're done.
done_testing();