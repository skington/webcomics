package webcomics;
use Dancer ':moose';
use Dancer::Plugin::Database qw();
use common::sense;

use Data::Dumper::Concise;
use DateTime;
use DateTime::Format::ISO8601;
use DateTime::Format::MySQL;
use English qw(-no_match_vars);
use Feed::Find;
use HTML::Entities;
use HTTP::Async;
use Image::Size;
use List::MoreUtils;
use LWP;
use Text::Sequence;
use URI;
use XML::Feed;

use WWW::Webcomic::Page;
use WWW::Webcomic::Site;

our $VERSION = '0.1';

get '/' => sub {
    my $filename_urls = config->{appdir} . '/urls';
    open(my $fh_urls, '<', $filename_urls)
        or debug("Couldn't open url file $filename_urls: $!");
    my %params;
    while (<$fh_urls>) {
        chomp;
        push @{ $params{urls} },
            {
            url => $_,
            got => Dancer::Plugin::Database::database->quick_select(
                'webcomic', { url_home => $_ }
            )
            };
    }
    close $fh_urls;
    template 'index', \%params;
};

get '/addnew' => sub {
    template 'addnew';
};

post '/addnew' => sub {
    addnew(params->{url});
};

get qr{/addnew/(?<url> .+)$}x => sub {
    addnew(captures->{url});
};

sub addnew {
    my ($url) = @_;

    # Fetch the URL, bomb out immediately if we couldn't get anything.
    # Parse this no matter what, as we want the title.
    my $site = WWW::Webcomic::Site->new(home_page => $url);
    my $contents = eval { $site->home_page->contents } or do {
        return template 'addnew_response',
            { error => 'invalid_url', url => $url, };
    };

    my %template_params;

    # Is there a RSS feed? If so, that's probably our best bet,
    # assuming the feed is germane (e.g. this isn't Doonesbury, which has
    # a standard Slate feed rather than its own)
    if (my %feed_contents = get_feed_contents($site)) {

        # Analyse each feed, trying to identify comics vs news vs comments,
        # and working out URL structures.
        my $feed_info = analyse_feed_contents(\%feed_contents);

        my $title_element
            = $site->home_page->tree->look_down(_tag => 'title');
        $template_params{title} = HTML::Entities::encode_entities(
            ($title_element->content_list)[0]);
        $template_params{url_home} = $url;
        $template_params{url_feed} = $feed_info->{feed};
        for my $field (map { 'regexstr_entry_' . $_ } qw(title link)) {
            $template_params{$field}
                = HTML::Entities::encode_entities($feed_info->{$field});
        }

        # Describe the entries briefly
        for my $entry (sort { $a->date <=> $b->date }
            @{ $feed_contents{ $feed_info->{feed} } })
        {
            # Hopefully we got a date from the feed. Otherwise, we'll have
            # to work it out from our regexstr.
            my $date = $entry->date;
            if (!$date) {
                field:
                for my $field (qw(link title)) {
                    my $matches = $entry->{matches}{$field}{values};
                    ### TODO: month_name, month_abbr, day_name, day_abbr
                    my $match_date;
                    eval {
                        $match_date = DateTime->new(
                            year  => $matches->{yyyy},
                            month => $matches->{mm} || $matches->{m},
                            day   => $matches->{dd} || $matches->{d},
                        );
                    };
                    if ($match_date) {
                        $date = $match_date;
                        last field;
                    }
                }
            }
            push @{ $template_params{entries} },
                {
                url_entry  => $entry->page->url,
                date_entry => $date
                ? DateTime::Format::MySQL->format_datetime($date)
                : '',
                title_entry => $entry->title,
                };
        }
        return template 'addnew_response', \%template_params;
    }

    # Extract all interesting-looking links.
    $template_params{links} = [
        identify_interesting_links(
            extract_links($url, $site->home_page->tree)
        )
    ];

    # Find the largest image on the page and find out how to identify
    # it.
    if (q{Care about this} eq q{A lot}) {
        my $largest_image = find_largest_image($url, $site->home_page->tree);
        $template_params{image} = $largest_image;

        # Work out how to identify this image.
        $template_params{identifiers} = [
            identifiers_from_element(
                $site->home_page->tree, $largest_image->{element}
            )
        ];
    }

    # Right, return our template.
    template 'addnew_response', \%template_params;
}

# Supplied with the URL of a page, and its contents, finds any RSS / Atom
# feeds and returns their contents, in the form of a hash of
# url => arrayref of entry hashrefs with the following keys:
#   title: title of the entry
#   link:  URL of the page linked to
#   date:  optional (missing in some feeds), the date posted

sub get_feed_contents {
    my ($site) = @_;

    my @feed_pages = $site->all_feed_pages;
    return if !@feed_pages;

    my %feed_contents;
    url:
    for my $page (@feed_pages) {
        $feed_contents{$page->url} = $page->entries;
    }
    return %feed_contents;
}

# Supplied with a hash of key => arrayref of feed entries, analyses each
# one in turn.

sub analyse_feed_contents {
    my ($feed_contents) = @_;

    # Find regexstrs for link and title in all feeds.
    # Work out which has been more effective overall, if any.
    my (%feed_matches, %field_matches);
    for my $feed (keys %$feed_contents) {
        analyse_feed_entries(@{ $feed_contents->{$feed} });
        for my $entry (@{ $feed_contents->{$feed} }) {
            for my $field (qw(link title)) {
                my $num_matches
                    = scalar keys %{ $entry->{matches}{$field}{values} };
                $feed_matches{$feed} += $num_matches;
                $field_matches{$field}{ $entry->{matches}{$field}{regexstr} }
                    += $num_matches;
                $field_matches{$field}{any}++ if $num_matches > 0;
            }
        }
    }

    # Work out what we're going to say about this.
    my %feed_info;
    $feed_info{feed} = (sort { $feed_matches{$b} <=> $feed_matches{$a} }
            keys %feed_matches)[0];
    my @useful_fields;
    my $better_field_title
        = $field_matches{title}{any} <=> $field_matches{link}{any};
    push @useful_fields, qw(title) if $better_field_title >= 0;
    push @useful_fields, qw(link)  if $better_field_title <= 0;
    for my $field (@useful_fields) {
        $feed_info{ 'regexstr_entry_' . $field } = (
            sort { $field_matches{$field}{$b} <=> $field_matches{$field}{$a} }
            grep { $_ ne 'any' }
            keys %{ $field_matches{$field} }
        )[0];
    }

    return \%feed_info;
}

# Supplied with a feed entry, analyses it working out
# details such as URL format, and likely nature of each entry (comic,
# news/rant or comments).

sub analyse_feed_entries {
    my (@entries) = @_;

    # Look for clues of the posted date in the link and/or the title.
    field:
    for my $field (qw(link title)) {

        # Go through each entry, finding regexstrs that match.
        # Whichever regexstr matches the most things, and the most often,
        # is presumably the best. In case of ties, prefer the more complete
        # regex.
        my %total_match_length;
        for my $entry (@entries) {
            regexstr:
            for my $regexstr (identify_date_regexstr($entry, $field)) {
                my %match_term;
                ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                ## no critic (RegularExpressions::RequireExtendedFormatting)
                eval { $entry->$field =~ qr/$regexstr/; %match_term = %+};
                ## use critic

                # Right, remember how useful this regexstr was.
                for my $match (values %match_term) {
                    $total_match_length{$regexstr} += length($match);
                }
            }
        }

        # See if there are any matches based on an ordinal number
        # increasing.
        my %sequence_regexstr_length
            = identify_sequence_regexstr(map { $_->$field } @entries);
        %total_match_length
            = (%total_match_length, %sequence_regexstr_length);

        my $regexstr_bestmatch = (
            sort {
                $total_match_length{$b} <=> $total_match_length{$a}
                    || length($b) <=> length($a)
                }
                keys %total_match_length
        )[0];
        next field if $total_match_length{$regexstr_bestmatch} == 0;

        # Now go through each entry applying the regexstr, now that we've
        # decided on a favourite.
        for my $entry (@entries) {
            ## no critic (RegularExpressions::RequireExtendedFormatting)
            $entry->$field =~ qr/$regexstr_bestmatch/;
            ## use critic
            my %matches = %+;
            $entry->{matches}{$field}
                = { regexstr => $regexstr_bestmatch, values => \%matches };
        }
    }
}

# Supplied with a string and a DateTime object object, returns a list
# of regexes that match the supplied string with the supplied DateTime
# object.

sub identify_date_regexstr {
    my ($entry, $field, $date) = @_;

    # If we weren't given a date, attempt to match on any date in the past
    # fortnight.
    if (!$entry->date && !$date) {
        my @regexstr_guesses;
        for my $delta_days (0 .. 13) {
            push @regexstr_guesses,
                identify_date_regexstr($entry, $field,
                DateTime->now->subtract(days => $delta_days));
        }
        return List::MoreUtils::uniq(@regexstr_guesses);
    }

    # OK, find regexstrs that match.
    ### FIXME: this ignores the date.
    return $entry->regexstrs_date($field);
}

# Supplied with a list of fields, attempts to identify sequences. If it finds
# any, returns a hash of regexstr => number of total characters matched.

sub identify_sequence_regexstr {
    my (@values) = @_;

    my ($sequences, $singletons) = Text::Sequence::find(@values);
    return if @$sequences == 0;
    my %sequence_regexstr_length;
    for my $sequence (@$sequences) {
        (my $regexstr = $sequence->re) =~ s/[(]/(?<seq>/;
        my $length_match;
        for my $value (@values) {
            my ($match) = $value =~ qr/$regexstr/;
            $length_match += length($match);
        }
        $sequence_regexstr_length{$regexstr} = $length_match;
    }
    return %sequence_regexstr_length;
}

# Supplied with a list of links, as returned by extract_links, returns
# only those that look interesting.

sub identify_interesting_links {
    my (@links) = @_;

    my @interesting_links;
    tag:
    for my $link (@links) {
        for my $attribute (keys %$link) {
            if ($link->{$attribute}
                =~ /(?: \b | _) (?: prev (?: ious)? | back ) \b /xi)
            {
                push @interesting_links, $link;
                next tag;
            }
        }
    }
    return @interesting_links;
}

# Supplied with a URL and a HTML::TreeBuilder tree, returns a list of
# hashes with the following keys:
#  url: the absolute URL for this URL
#  text: the text of the link
#  css: the CSS for this element
#  rel: any rel attributes

sub extract_links {
    my ($url, $tree) = @_;

    my @links = $tree->look_down(_tag => 'a');
    my @link_data;
    for my $link (@links) {
        my %link_data = ( url => URI->new_abs($link->attr('href'), $url) );
        for my $attribute ('class', 'id', 'rel') {
            if ($link->attr($attribute)) {
                $link_data{$attribute} = $link->attr($attribute);
            }
        }
        if (my $image = $link->look_down(_tag => 'img')) {
            $link_data{img_alt} = $image->attr('alt');
            $link_data{img_src} = URI->new_abs($image->attr('src'), $url);
        }
        if (my $text = $link->as_text) {
            $link_data{text} = $text;
        }
        push @link_data, \%link_data;
    }
    return @link_data;
}

# Supplied with a URL and a HTML::TreeBuilder tree, returns a hashref with the
# following fields:
#   element: HTML::Element object for the <img> tag
#   url: the absolute URL for this URL
#   area: the number of pixels taken up by this image.
#   width: the width of this image
#   height: the height of this image

sub find_largest_image {
    my ($url, $tree) = @_;

    # First, fish out any <img> tags from our web page.
    my @img_elements = $tree->look_down(_tag => 'img');

    # Now fetch them in parallel.
    my @images;
    my %image_by_id;
    my $async = HTTP::Async->new;
    my %seenelement;
    element:
    for my $element (@img_elements) {
        my $image_info = {
            element => $element,
            url     => URI->new_abs($element->attr('src'), $url),
        };

        # Don't bother fetching e.g. spacer gifs (seriously, guys?
        # spacer gifs in the 2010s?)
        next element
            if $seenelement{ $image_info->{url} }
                || $image_info->{url} =~ / paypal[.]com /x;
        print STDERR 'Having a look at image ', $image_info->{url}, "\n";
        my $async_id
            = $async->add(HTTP::Request->new(GET => $image_info->{url}));
        $image_by_id{$async_id} = $image_info;
        push @images, $image_info;
    }

    # Fish them out as our requests complete.
    response:
    while (my ($response, $id) = $async->wait_for_next_response) {
        print STDERR 'Got response for ', $image_by_id{$id}{url}, "\n";
        if (!$response->is_success) {
            print STDERR q{Couldn't fetch }, $image_by_id{$id}{url}, ': ',
                $response->status_line, "\n";
            next response;
        }
        my $contents = $response->content // $response->decoded_content;
        if (!$contents) {
            print STDERR "Strange response:\n", Dumper($response), "\n";
            next response;
        }
        my $image_info = $image_by_id{$id};
        @$image_info{qw(width height)} = Image::Size::imgsize(\$contents);
        if (!defined $image_info->{width}) {
            print STDERR "What's up with this response then?\n",
                Dumper($response), "\n";
        }
        $image_info->{area} = $image_info->{width} * $image_info->{height};
    }

    # Find the largest image of them all - presumably the comic.
    for my $image (@images) {
        printf "%s: %d x %d = %d\n", @$image{qw(url width height area)}
    }
    my ($largest_image) = (sort { $b->{area} <=> $a->{area} } @images)[0];
    return $largest_image;
}

# Supplied with an HTML::TreeBuilder tree, and an element from the
# tree, return the minimal set of identifiers needed to
# locate it (e.g. ids, classes or tags)

sub identifiers_from_element {
    my ($tree, $element) = @_;

    my ($path_identified, @identifiers);
    element:
    while ($element && !$path_identified) {

        # Anything with an ID can be assumed to be unique.
        if (my $id = $element->attr('id')) {
            unshift @identifiers, { id => $id };
            $path_identified = 1;

        } elsif (my $class = $element->attr('class')) {

            # The class might only be used once, in which case it's as
            # good as an Id.
            unshift @identifiers, { tag => $element->tag, class => $class };
            my @elements_with_class = $tree->look_down(class => $class);
            if (@elements_with_class == 1) {
                $path_identified = 1;
            }

        } else {

            # Or this could be a totally unhelpful element like an empty
            # div or something.
            unshift @identifiers, { tag => $element->tag };
        }

        # Look up one level if we didn't find anything immediately.
        if (!$path_identified) {
            ($element) = $element->lineage;
        }
    }
    return @identifiers;
}

post '/create' => sub {
    my $database = Dancer::Plugin::Database::database();
    $database->quick_insert(
        'webcomic',
        {
            map { $_ => params->{$_} }
                qw(title url_home url_feed
                regexstr_entry_link regexstr_entry_title)
        }
    );
    # Fuck you, Tim Bunce; why make me specify these useless parameters?
    my $webcomic_id = $database->last_insert_id(undef, undef, undef, undef);
    for my $entryparam (sort grep { /^entry_/ && params->{$_} } params) {
        (my $dateparam = $entryparam) =~ s/entry/entrydate/;
        $database->quick_insert(
            'entry',
            {
                webcomic_id => $webcomic_id,
                url_entry   => params->{$entryparam},
                date_entry  => params->{$dateparam},
            }
        );
    }
};

true;
