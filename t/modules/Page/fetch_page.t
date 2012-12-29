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
my $page_contents = $page->_fetch_page;
ok($page_contents, 'We got something from fetch_page');
my $re_html_like = qr{.* < \s* html [^>]* > }xsm;
like($page_contents, $re_html_like, 'Looks like HTML');

# Fetching the contents attribute will lazily fetch the page for us.
my $lazy_page = WWW::Webcomic::Page->new(url => 'http://www.google.com');
my $lazy_page_contents = $lazy_page->contents;
ok($lazy_page_contents, 'We can get the page contents lazily');
like($page_contents, $re_html_like, 'Lazy page looks like HTML also');

# Neither of these objects have a tree attribute yet.
ok(!$page->has_tree, 'No tree object for explicit page object');
ok(!$lazy_page->has_tree, 'No tree object for lazy page object');

# The tree attribute auto-vivifies, and can be used to fetch the title
# of the page.
ok($page->tree, 'We can get a tree for our page');
isa_ok($page->tree, 'HTML::TreeBuilder');
my $element_title = $page->tree->look_down(_tag => 'title');
ok($element_title, 'We can look down the tree for a title');
isa_ok($element_title, 'HTML::Element');
is_deeply($element_title->content_list, 'Google', 'This looks like Google');

# And we're done.
done_testing();