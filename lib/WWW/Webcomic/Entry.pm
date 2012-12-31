package WWW::Webcomic::Entry;

use strict;
use warnings;
no warnings qw(uninitialized);
use vars qw($VERSION);
use English qw(-no_match_vars);

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::LazyRequire;
use WWW::Webcomic::MooseTypes;

use Carp;

=head1 NAME

WWW::Webcomic::Entry - an individual entry in a webcomic

=head1 DESCRIPTION

A Moose class representing an individual entry (typically a daily comic)
belonging to a webcomic. It also knows how to generate regexes that match
the components of an entry, either based on dates or sequences. It does
so in the form of regexstrs - string representations of regexes -
rather than regexes themselves, because regexstrs need to be able to be
subsequently manipulated by regexes.

=head2 Attributes

=over

=item title

The title of this entry. Can be blank or unhelpful (e.g. just the date,
with some random furniture like 'Comic for ...'). Not to be confused with
title text.

=cut

has 'title' => (
    is  => 'rw',
    isa => 'Str',
);

=item page

The page this entry refers to. A WWW::Webcomic::Page object.

=cut

has 'page' => (
    is            => 'rw',
    isa           => 'WWW::Webcomic::Page',
    lazy_required => 1,
);

=item date

The date this entry was originally posted. A DateTime object.

=cut

has 'date' => (
    is        => 'rw',
    isa       => 'DateTime',
    predicate => 'has_date',
);

=back

=head2 Object methods

=over

=item link

A shortcut for $entry->page->url

=cut

sub link {
    my ($self) = @_;

    return $self->page->url;
}

=item regexstr_literal

 In: $field
 Out: @regexstr

Supplied with a field name - either title or link - returns a list of
regexstrs that match it.

### TODO: get rid of the link method, pass page->url or title directly.

=cut

sub regexstr_literal {
    my ($self, $field) = @_;

    if (!$field || !($field ~~ ['title', 'link'])) {
        carp "Unexpected field [$field] supplied - expected title or link";
        return;
    }

    # Using quotemeta here because \Q and \E act after the parser has looked
    # for e.g. slashes, so saying qr/\Qhttp://...\E/ won't parse.
    my $raw_field = $self->$field;
    if (ref($raw_field) eq 'URI::http') {
        $raw_field = $raw_field->as_string;
    }
    my @regexstr = ('^' . quotemeta($raw_field) . '$');
    return @regexstr;
}

=item date_matches

 In: $date (optional)
 Out: @date_matches

Returns a list of date matches corresponding to a particular date - either
the date supplied, or the entry's date. If no date can be found, returns
an empty list.

Date matches are hashes as follows:

=over

=item name

The name of the match. One of:

=over

=item years

=over

=item yyyy

A 4-digit year.

=back

=item months

=over

=item m

The month number.

=item mm

The month number, zero-padded.

=item month_name

The full name of the month.

=item month_abbr

An abbreviated version of the name of the month.

=back

=item days

As months, but C<d>, C<dd>, C<day_name> and C<day_abbr>

=back

=item value

The value of the date field - e.g. 2012 for yyyy, 9 for m, 09 for mm,
September for month_name, Sep for month_abbr etc.

=item regexstr

A string representing the snippet of a regex required to match such
a value. This is a named capture, whose name is the name of the date match.
For instance: '(?<yyyy> \d{4} )' or '(?<mm> \d{2} )'

=back

=cut

sub date_matches {
    my ($self, $date) = @_;

    # Make sure we have a date.
    if (!$date && $self->has_date) {
        $date = $self->date;
    }
    return if !$date;

    # OK, build our look-up table.
    return (
        # Years.
        { name => 'yyyy', value => $date->year,  regexstr => '\d{4}' },

        # Months.
        { name => 'm',    value => $date->month, regexstr => '\d{1,2}' },
        {
            name     => 'mm',
            value    => sprintf('%02d', $date->month),
            regexstr => '\d{2}'
        },
        {
            name     => 'month_name',
            value    => $date->month_name,
            regexstr => '\w+?'
        },
        {
            name     => 'month_abbr',
            value    => $date->month_abbr,
            regexstr => '\w+?'
        },

        # Days.
        { name => 'd', value => $date->day, regexstr => '\d{1,2}' },
        {
            name     => 'dd',
            value    => sprintf('%02d', $date->day),
            regexstr => '\d{2}'
        },
        { name => 'day_name', value => $date->day_name, regexstr => '\w+?' },
        { name => 'day_abbr', value => $date->day_abbr, regexstr => '\w+?' },
    );
}

=item regexstr_matching

 In: \@regexstr
 In: \%match
 Out: @regexstr_matching

Supplied with an arrayref of regexstrs and a match hashref (as returned
by date_match above), returns an additional list of regexstrs that match
the match hashref.

e.g. if supplied with

 [ '^http::\/\/www.foo.com\/comic\/20121231$' ]

and

 {
     name => 'm',
     value => '12',
     regexstr => '\d{1,2}'
 }

would return

 (
     '^http::\/\/www.foo.com\/comic\/20(?<m> \d{1,2} )1231$',
     '^http::\/\/www.foo.com\/comic\/2012(?<m> \d{1,2} )31$',
 )

=cut

sub regexstr_matching {
    my ($self, $regexstr, $match) = @_;

    # Build a regex that will match the value we're looking for.
    ## no critic (ValuesAndExpressions::RequireInterpolationOfMetachars)
    my $regex_match = eval('qr/\Q' . $match->{value} . '\E/i');
    ## use critic
    my $regexstr_match = eval(
        sprintf('qr/(?<%s> %s )/x', $match->{name}, $match->{regexstr})
    );

    # Build revised regexstrs that match this match term - there might
    # be many, which is fine (for e.g. a value between 1 and 12 that
    # can match both months and days). Some of these won't be valid,
    # either - e.g. "(?<month>...)" will be in turn matched by
    # day_abbr, becoming "(?<(?<day_abbr> \w+?)th...))".
    # That's fine, we can catch errors; it's easier than not matching
    # anything within brackets.
    my @regexstr_revised;
    for my $regexstr (@$regexstr) {
        while ($regexstr =~ m/$regex_match/g) {

            # Replace the literal in the regex with a parametrised
            # match for the term.
            my $regexstr_matchterm = $regexstr;
            substr($regexstr_matchterm, $LAST_MATCH_START[0],
                length($match->{value})) = $regexstr_match;
            push @regexstr_revised, $regexstr_matchterm;
        }
    }
    return @regexstr_revised;
}


=back

=head1 VERSION

This is version 0.02.

=cut

$VERSION = '0.02';

__PACKAGE__->meta->make_immutable;
1;