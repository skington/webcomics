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

=item regexstrs_date

 In: $field
 Out: @regexstr

Supplied with a field name - either C<title> or C<link> - returns a list
of regexstrs that match it. There should normally just be three - the literal
regexstr, a regexstr that matches the date, and a regexstr that matches
the literal prefix and suffix and the date - but you can
occasionally see more, e.g. when the day part of the month is between 1
and 12 so could conceivably match either day or month, or if a date
is unnecessarily complex, e.g. 'Monday, December 31 2012'.

=cut

sub regexstrs_date {
    my ($self, $field) = @_;

    $self->_sanity_check_field($field) or return;

    # Build up a list of regexes that match this string, starting with
    # the obvious "it's this string" one, and cumulatively trying to match
    # more data parts.
    my @regexstr = $self->regexstr_literal($field);

    # Go through all the regexstrs that match components of this date.
    # Some of them will result in false positives, but with enough
    # strings to go by we should spot a common pattern.
    for my $match ($self->date_matches($self->date)) {
        push @regexstr, $self->regexstr_matching(\@regexstr, $match);
    }

    # URLs could have non-date-related content (e.g. PvP has a version
    # of the title in the URL), so make another less-specific version of
    # the regex that only includes the matches.
    my @regexstr_shorter;
    for my $regexstr (@regexstr) {
        push @regexstr_shorter, $regexstr =~ m{ ( [(] .+ [)] ) }x;
    }
    push @regexstr, @regexstr_shorter;

    # Weed out regexstrs that only have partial dates - that's no use.
    @regexstr = $self->regexstrs_no_partial_dates($field, @regexstr);

    return @regexstr;
}

=item regexstr_literal

 In: $field
 Out: @regexstr

Supplied with a field name - either title or link - returns a list of
regexstrs that match it. (Just the one, obviously, but all other regexstr_
methods return lists.)

### TODO: get rid of the link method, pass page->url or title directly.

=cut

sub regexstr_literal {
    my ($self, $field) = @_;

    $self->_sanity_check_field($field) or return;
    
    # Using quotemeta here because \Q and \E act after the parser has looked
    # for e.g. slashes, so saying qr/\Qhttp://...\E/ won't parse.
    my $raw_field = $self->$field;
    if (ref($raw_field) eq 'URI::http') {
        $raw_field = $raw_field->as_string;
    }
    my @regexstr = ('^' . quotemeta($raw_field) . '$');
    return @regexstr;
}

sub _sanity_check_field {
    my ($self, $field) = @_;

    if (!$field || !($field ~~ ['title', 'link'])) {
        carp "Unexpected field [$field] supplied - expected title or link";
        return;
    }
    return $field;
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

=item yy

A 2-digit year.

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
        { name => 'yyyy', value => $date->year, regexstr => '\d{4}' },
        {
            name     => 'yy',
            value    => sprintf('%02d', $date->year % 100),
            regexstr => '\d{2}'
        },

        # Months.
        { name => 'm', value => $date->month, regexstr => '\d{1,2}' },
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
        {   
            name     => 'day_name',
            value    => $date->day_name,
            regexstr => '\w+?'
        },
        {
            name     => 'day_abbr',
            value    => $date->day_abbr,
            regexstr => '\w+?'
        },
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

=item regexstrs_no_partial_dates

 In: $field
 In: @regexstrs
 In: @regexstrs_no_partial_dates

Supplied with a field (C<link> or C<title> as above), and a list of regexstrs,
returns a list of regexstrs that either matches no date components, or matches
all three (year, month and day, in whichever permutation).

There are two reasons why you might have this. First of all, the process of
building up regexstrs iterates through all the possible date components, and
will produce intermediate results - e.g. a regexstr matching only the day,
but not the month or year - even if it eventually finds a regexstr that
matches all three. Once we have the latter, we don't need the former, but
we only know we have a perfect match at the end of the process.

Secondly, the process might find a false match for a day or month name
or abbreviation - e.g. if a title containing 'Mnemonic' was posted on a
Monday, or the word 'Decrepit' featured during the month of December.
These are also no good.

=cut

sub regexstrs_no_partial_dates {
    my ($self, $field, @regexstr) = @_;

    $self->_sanity_check_field($field) or return;

    my @valid_regexstr;
    regexstr:
    for my $regexstr (@regexstr) {
        # Find out what this regexstr matches on the current field.
        my %field_matched;
        eval { $self->$field =~ /$regexstr/; %field_matched = %+; 1 }
            or next regexstr;

        # Build up a list of the date components that we had matches for.
        my $found_date_component = 0;
        date_component:
        for my $date_component (
            ['yyyy', 'yy'],
            [qw(m mm month_name month_abbr)],
            [qw(d dd day_name day_abbr)]
            )
        {
            for my $component_name (@$date_component) {
                if ($field_matched{$component_name}) {
                    $found_date_component++;
                    next date_component;
                }
            }
        }

        # None or 3 are fine; anything else is an unhelpful partial
        # match that we don't want.
        if ($found_date_component ~~ [0, 3]) {
            push @valid_regexstr, $regexstr;
        }
    }
    return @valid_regexstr;

}


=back

=head1 VERSION

This is version 0.02.

=cut

$VERSION = '0.02';

__PACKAGE__->meta->make_immutable;
1;