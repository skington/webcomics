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

=item date_match

 In: $date (optional)
 Out: %date_match

Returns a hash of date matches corresponding to a particular date - either
the date supplied, or the entry's date. If no date can be found, returns
an empty list.

The keys of the hash are date part abbreviations:

=over

=item

C<yyyy> (four-digit year)

=item

C<m>, C<mm>, C<month_name> and C<month_abbr>: month number, straight or
padded with zeroes; month name, full or abbreviated

=item

C<d>, C<dd>, C<day_name> and C<day_abbr>: as above, but for days

=back

The values are hashrefs with two fields:

=over

=item value

The value of the date field - e.g. 2012 for yyyy, 9 for m, 09 for mm,
September for month_name, Sep for month_abbr etc.

=item regexstr

A string representing the snippet of a regex required to match such
a value.

=back

=cut

sub date_match {
    my ($self, $date) = @_;

    # Make sure we have a date.
    if (!$date && $self->has_date) {
        $date = $self->date;
    }
    return if !$date;

    # OK, build our look-up table.
    return (
        yyyy => { value => $date->year,  regexstr => '\d{4}' },
        m    => { value => $date->month, regexstr => '\d{1,2}' },
        mm   => {
            value    => sprintf('%02d', $date->month),
            regexstr => '\d{2}'
        },
        d  => { value => $date->day, regexstr => '\d{1,2}' },
        dd => {
            value    => sprintf('%02d', $date->day),
            regexstr => '\d{2}'
        },
        month_name => { value => $date->month_name, regexstr => '\w+?' },
        month_abbr => { value => $date->month_abbr, regexstr => '\w+?' },
        day_name   => { value => $date->day_name,   regexstr => '\w+?' },
        day_abbr   => { value => $date->day_abbr,   regexstr => '\w+?' },
    );
}

=back

=head1 VERSION

This is version 0.02.

=cut

$VERSION = '0.02';

__PACKAGE__->meta->make_immutable;
1;