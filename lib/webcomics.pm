package webcomics;
use Dancer ':moose';
use Dancer::Plugin::Database qw();
use common::sense;

use Data::Dumper::Concise;
use DateTime;
use DateTime::Format::MySQL;
use English qw(-no_match_vars);
use Feed::Find;
use HTML::Entities;
use HTML::TreeBuilder;
use HTTP::Async;
use Image::Size;
use LWP;
use URI;
use XML::Feed;

our $VERSION = '0.1';

get '/' => sub {
    my $filename_urls = config->{appdir} . '/urls';
    open(my $fh_urls, '<', $filename_urls)
        or debug("Couldn't open url file $filename_urls: $!");
    my %params;
    while (<$fh_urls>) {
        chomp;
        push @{ $params{urls} }, { url => $_ };
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
    my $contents = get_page($url) or do {
        return template 'addnew_response',
            { error => 'invalid_url', url => $url, };
    };

    my %template_params;

    # Is there a RSS feed? If so, that's probably our best bet,
    # assuming the feed is germane (e.g. this isn't Doonesbury, which has
    # a standard Slate feed rather than its own)
    if (my %feed_contents = get_feed_contents($url, $contents)) {

        # Analyse each feed, trying to identify comics vs news vs comments,
        # and working out URL structures.
        my $feed_info = analyse_feed_contents(\%feed_contents);

        $template_params{url_home} = $url;
        $template_params{url_feed} = $feed_info->{feed};
        for my $field (map { 'regexstr_entry_' . $_ } qw(title link)) {
            $template_params{$field}
                = HTML::Entities::encode_entities($feed_info->{$field});
        }

        # Describe the entries briefly
        for my $entry (sort { $a->{date} <=> $b->{date} }
            @{ $feed_contents{ $feed_info->{feed} } })
        {
            push @{ $template_params{entries} },
                {
                url_entry => $entry->{link},
                date_entry =>
                    DateTime::Format::MySQL->format_datetime($entry->{date})
                };
        }
        return template 'addnew_response', \%template_params;
    }

    # Right, time to parse this web page.
    my $tree = HTML::TreeBuilder->new;
    $tree->parse($contents);

    # Find the largest image on the page and find out how to identify
    # it.
    my $largest_image = find_largest_image($url, $tree);
    $template_params{image} = $largest_image;

    # Work out how to identify this image.
    $template_params{identifiers}
        = [identifiers_from_element($tree, $largest_image->{element})];

    # We're done with our tree, so delete it to free up memory.
    $tree->delete;

    # Right, return our template.
    template 'addnew_response', \%template_params;
}

sub get_page {
    my ($url) = @_;

    my $ua       = user_agent();
    my $response = $ua->get($url);
    if (!$response->is_success) {
        print STDERR "Couldn't fetch $url: ", $response->status_line, "\n";
        return;
    }
    return $response->decoded_content // $response->content;
}

{
    my $ua;

    sub user_agent {
        return $ua if $ua;
        $ua = LWP::UserAgent->new;
        $ua->agent('Webcomics parser/' . $VERSION);
        return $ua;
    }
}

# Supplied with the URL of a page, and its contents, finds any RSS / Atom
# feeds and returns their contents, in the form of a hash of
# url => arrayref of entry hashrefs with the following keys:
#   title: title of the entry
#   link:  URL of the page linked to
#   date:  optional (missing in some feeds), the date posted

sub get_feed_contents {
    my ($url, $html_mainpage) = @_;

    my @feed_urls = Feed::Find->find_in_html(\$html_mainpage, $url);
    return if !@feed_urls;

    my %feed_contents;
    url:
    for my $url (@feed_urls) {

        # webcomicsnation.com and possibly others decide to brush you off
        # if you use the default libwww/perl user agent.
        ## no critic (Variables::ProtectPrivateVars)
        local *LWP::UserAgent::_agent = sub {
            'Who the hell bans automated access to RSS feeds?'
        };
        ## use critic
        my $feed = XML::Feed->parse(URI->new($url)) or do {
            print STDERR "Couldn't parse $url\n";
            next url;
        };
        for my $entry ($feed->entries) {

            # The link might be a feedproxy link, which is no use; we want
            # the ultimate URL, without any of that tracking nonsense.
            my $link = $entry->link;
            if ($link =~ /feedproxy/) {
                my $response = user_agent->get($link);
                $link = $response->base;
                for my $keyword (qw(source medium campaign)) {
                    $link =~ s{
                        ( [?] .*? )
                        utm_$keyword = [^&]+
                        (?: & | $)
                    }{$1}x;
                }
                $link =~ s/[?]$//;
            }
            push @{ $feed_contents{$url} },
                {
                title => $entry->title,
                link  => $link,
                date  => $entry->issued,
                };
        }
    }

    return %feed_contents;
}

# Supplied with a hash of key => arrayref of feed entries, analyses each
# one in turn.

sub analyse_feed_contents {
    my ($feed_contents) = @_;

    # Prune our feeds beforehand if we can.
    for my $feed (keys %$feed_contents) {

        # Discard out of hand any feed that doesn't even have dates.
        # That means you, xkcd Atom feed.
        delete $feed_contents->{$feed} if !$feed_contents->{$feed}[0]{date};

        # Ignore feeds that are blatantly comments-only feeds (e.g.
        # Skin Horse).
        delete $feed_contents->{$feed} if $feed =~ / \b comment s? \b /x;
    }

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
            for my $regexstr (
                identify_date_regexstr($entry->{$field}, $entry->{date}))
            {
                my %match_term;
                ## no critic (ErrorHandling::RequireCheckingReturnValueOfEval)
                ## no critic (RegularExpressions::RequireExtendedFormatting)
                eval { $entry->{$field} =~ qr/$regexstr/; %match_term = %+};
                ## use critic

                # To weed out false positives (e.g. 'Mnemonics' matching
                # day_abbr), make sure we have a full date.
                my $found_set_member;
                match_set:
                for my $match_set (
                    ['yyyy'],
                    [qw(m mm month_name month_abbr)],
                    [qw(d dd day_name day_abbr)]
                    )
                {
                    for my $match_term (@$match_set) {
                        if ($match_term{$match_term}) {
                            $found_set_member++;
                            next match_set;
                        }
                    }
                }
                next regexstr if $found_set_member != 3;

                # Right, remember how useful this regexstr was.
                for my $match (values %match_term) {
                    $total_match_length{$regexstr} += length($match);
                }
            }
        }

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
            $entry->{$field} =~ qr/$regexstr_bestmatch/;
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
    my ($string, $datetime) = @_;

    return if !$datetime;

    # Build up a list of regexes that match this string, starting with
    # the obvious "it's this string" one, and cumulatively trying to match
    # more data parts.
    # "regexstr" because this is a string representing a regex,
    # not an actual regex object.
    # And using quotemeta because \Q and \E act after the parser has looked
    # for e.g. slashes, so saying qr/\Qhttp://...\E/ won't parse.
    my @regexstr = ('^' . quotemeta($string) . '$');

    # And here's a bunch of matches we'll look for.
    # Some of them will result in false positives, but with enough
    # strings to go by we should spot a common pattern.
    my %match = (
        yyyy => { value => $datetime->year,  regexstr => '\d{4}' },
        m    => { value => $datetime->month, regexstr => '\d{1,2}' },
        mm   => {
            value    => sprintf('%02d', $datetime->month),
            regexstr => '\d{2}'
        },
        d  => { value => $datetime->day, regexstr => '\d{1,2}' },
        dd => {
            value    => sprintf('%02d', $datetime->day),
            regexstr => '\d{2}'
        },
        month_name => { value => $datetime->month_name, regexstr => '\w+?' },
        month_abbr => { value => $datetime->month_abbr, regexstr => '\w+?' },
        day_name   => { value => $datetime->day_name,   regexstr => '\w+?' },
        day_abbr   => { value => $datetime->day_abbr,   regexstr => '\w+?' },
    );

    # Go through each of them looking for matches.
    # For efficiency, try the longest match values first, to reduce
    # false positives when e.g. the day of the month is 1 or something
    # unhelpful like that.
    # We'll maintain a cumulative list of regexstrs that match; at the end,
    # the most complex *and* reliable will win out.
    for my $match_term (
        sort { length($match{$b}{value}) <=> length($match{$a}{value}) }
        keys %match
        )
    {

        # Build a regex that will match the value we're looking for.
        ## no critic (ValuesAndExpressions::RequireInterpolationOfMetachars)
        my $regex_match = eval('qr/\Q' . $match{$match_term}{value} . '\E/i');
        ## use critic
        my $regexstr_match = eval(
            sprintf(
                'qr/(?<%s> %s )/x',
                $match_term, $match{$match_term}{regexstr}
            )
        );

        # Build revised regexstrs that match this match term - there might
        # be many, which is fine (for e.g. a value between 1 and 12 that
        # can match both months and days). Some of these won't be valid,
        # either - e.g. "(?<month>...)" will be in turn matched by
        # day_abbr, becoming "(?<(?<day_abbr> \w+?)th...))".
        # That's fine, we can catch errors; it's easier than not matching
        # anything within brackets.
        my @regexstr_revised;
        for my $regexstr (@regexstr) {
            while ($regexstr =~ m/$regex_match/g) {

                # Replace the literal in the regex with a parametrised
                # match for the term.
                my $regexstr_matchterm = $regexstr;
                substr($regexstr_matchterm, $LAST_MATCH_START[0],
                    length($match{$match_term}{value}),
                    $regexstr_match);
                push @regexstr_revised, $regexstr_matchterm;
            }
        }

        # Add on these revised regex strings.
        @regexstr = (@regexstr, @regexstr_revised);
    }

    # URLs could have non-date-related content (e.g. PvP has a version
    # of the title in the URL), so make another less-specific version of
    # the regex that only includes the matches.
    my @regexstr_shorter;
    for my $regexstr (@regexstr) {
        push @regexstr_shorter, $regexstr =~ m{ ( [(] .+ [)] ) }x;
    }

    # Right, we're all done. Return this.
    return @regexstr, @regexstr_shorter;
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
