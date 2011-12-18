package webcomics;
use Dancer ':moose';
use common::sense;

use Data::Dumper::Concise;
use HTML::TreeBuilder;
use HTTP::Async;
use Image::Size;
use LWP;
use Moose;
use URI;

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
    my $tree = HTML::TreeBuilder->new;
    $tree->parse($contents);

    # Right, find the largest image on the page and find out how to identify
    # it.
    my $largest_image = find_largest_image($url, $tree);
    my $element = $largest_image->{element};
    my ($path_identified, @identifiers);
    element:
    while ($element && !$path_identified) {

	# Anything with an ID can be assumed to be unique.
	if (my $id = $element->attr('id') ) {
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
    $tree->delete;
    template 'addnew_response',
	{ image => $largest_image, identifiers => \@identifiers };
}

sub get_page {
    my ($url) = @_;

    my $ua = user_agent();
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
	next element if $seenelement{$image_info->{url}}
	    || $image_info->{url} =~ / paypal[.]com /x;
	print STDERR 'Having a look at image ', $image_info->{url}, "\n";
	my $async_id =
	    $async->add(HTTP::Request->new(GET => $image_info->{url}));
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

true;
