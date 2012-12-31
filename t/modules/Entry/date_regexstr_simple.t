#!/usr/bin/env perl
# Test simple date-matching regexstrs.

use strict;
use warnings;
no warnings qw(uninitialized);

use lib::abs qw(../../../lib ../../lib);
use Utils qw(_directory_is_safe);

use DateTime;
use Test::More;

use_ok('WWW::Webcomic::Entry');
use_ok('WWW::Webcomic::Page');

# Girl Genius is very simple: date components at the end of the URL,
# and at the end of the title, in different formats.
my $entry = WWW::Webcomic::Entry->new(
    date => DateTime->new(
        hour   => 5,
        minute => 0,
        second => 0,
        day    => 31,
        month  => 12,
        year   => 2012
    ),
    title => 'Girl Genius for Monday, December 31, 2012',
    page  => WWW::Webcomic::Page->new(
        url => 'http://www.girlgeniusonline.com/comic.php?date=20121231'
    ),
);
ok($entry, 'We have an Entry object that looks sane');

my %parts = (
    url_prefix => '^http\:\/\/www\.girlgeniusonline\.com\/comic\.php\?date\=',
    url_literal   => '20121231$',
    title_prefix  => '^Girl\ Genius\ for\ ',
    title_literal => 'Monday\,\ December\ 31\,\ 2012$',
    comma         => '\,\ ',
    space         => '\ ',
    year          => '(?^x:(?<yyyy> \d{4} ))',
    m             => '(?^x:(?<m> \d{1,2} ))',
    mm            => '(?^x:(?<mm> \d{2} ))',
    d             => '(?^x:(?<d> \d{1,2} ))',
    dd            => '(?^x:(?<dd> \d{2} ))',
    d_literal     => '31',
    day_literal   => 'Monday',
    day_abbr      => '(?^x:(?<day_abbr> \w+? ))day',
    day_name      => '(?^x:(?<day_name> \w+? ))',
    month_abbr    => '(?^x:(?<month_abbr> \w+? ))ember',
    month_name    => '(?^x:(?<month_name> \w+? ))',
);

# Start off with the literal regexstrs. These are just the initial value
# backslashed to hell.
my @regexstr_title_literal = $entry->regexstr_literal('title');
is_deeply(
    \@regexstr_title_literal,
    [_regexstr_array([qw(title_prefix title_literal)])],
    'Literal regexstr for title looks correct'
);

my @regexstr_link_literal = $entry->regexstr_literal('link');
is_deeply(
    \@regexstr_link_literal,
    [_regexstr_array([qw(url_prefix url_literal)])],
    'Literal regexstr for link looks correct'
);

# For the link, we expect the following:
# * the literal regexstr
# * four fully-matching date regexstrs, a combination of normal and
#   zero-padded, standalone;
# * the same date regexstrs, but as part of the link.

my @regexstr_link = $entry->regexstrs_date('link');
my @regexstr_date_components
    = _regexstr_array(
        [qw(year m d)],  [qw(year mm d)],
        [qw(year m dd)], [qw(year mm dd)]
    );
my @regexstr_link_expected = (
    _regexstr_array([qw(url_prefix url_literal)]),
    @regexstr_date_components,
    map { $parts{url_prefix} . $_ . '$' } @regexstr_date_components
);
is_deeply(
    [sort @regexstr_link],
    [sort @regexstr_link_expected],
    'Link date regexstrs are as we expect'
    )
    or diag("Got the following link date regexstrs: ",
    join("\n", sort @regexstr_link));

# For the month, we expect the following:
# * the literal regexstr
# * a combination of abbreviated and full day and month names,
#   and literal, normal and zero-padded day, standalone;
# * as above, but as part of the title, and with literal day names
#   as well.
my @regexstr_title = $entry->regexstrs_date('title');
my @regexstr_title_components_minimal = _regexstr_array(
    [qw(month_abbr space d comma year)],
    [qw(month_abbr space dd comma year)],
    [qw(month_name space d comma year)],
    [qw(month_name space dd comma year)],
);

my @regexstr_title_components = _regexstr_array(
    [qw(day_abbr comma month_abbr space d comma year)],
    [qw(day_abbr comma month_abbr space dd comma year)],
    [qw(day_abbr comma month_name space d comma year)],
    [qw(day_abbr comma month_name space dd comma year)],
    [qw(day_abbr comma month_abbr space d_literal comma year)],
    [qw(day_abbr comma month_name space d_literal comma year)],

    [qw(day_name comma month_abbr space d comma year)],
    [qw(day_name comma month_abbr space dd comma year)],
    [qw(day_name comma month_name space d comma year)],
    [qw(day_name comma month_name space dd comma year)],
    [qw(day_name comma month_abbr space d_literal comma year)],
    [qw(day_name comma month_name space d_literal comma year)],
);
my @regexstr_title_expected = (
    _regexstr_array([qw(title_prefix title_literal)]),
    @regexstr_title_components_minimal,
    @regexstr_title_components,
    (
        map {
            $parts{title_prefix}
                . $parts{day_literal}
                . $parts{comma}
                . $_ . '$'
            } @regexstr_title_components_minimal
    ),
    (
        map {
            $parts{title_prefix} . $_ . '$'
            } @regexstr_title_components
    ),
);
is_deeply(
    [sort @regexstr_title],
    [sort @regexstr_title_expected],
    'Title regexstrs are as we expect'
    )
    or diag(
    "Got the following title date regexstrs:\n",
    join("\n", sort @regexstr_title),
    "\n\nExpected:\n", join("\n", sort @regexstr_title_expected)
    );

done_testing();

sub _regexstr_array {
    my @regexstr;
    for my $part_sequence (@_) {
        push @regexstr, join('', map { $parts{$_} || $_ } @$part_sequence);
    }
    return sort @regexstr;
}

