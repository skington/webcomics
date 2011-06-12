package webcomics;
use common::sense;
use Dancer ':moose';

use Moose;
use LWP;

our $VERSION = '0.1';

get '/' => sub {
    template 'index';
};

get '/addnew' => sub {
    template 'addnew';
};

post '/addnew' => sub {
    my $url = params->{url};
    my $contents = get_page($url) or do {
	return template 'addnew_response',
	    {
	    error => 'invalid_url',
	    url   => $url,
	    stuff => 'bad things'
	    };
    };
    template 'addnew_response', { stuff => 'nonsense' };
};

sub get_page {
    my ($url) = @_;

    my $ua = user_agent();
    my $response = $ua->get($url);
    if (!$response->is_success) {
	return;
    }
    return $response->decoded_content;
}

{
    my $ua;
    sub user_agent {
	return $ua if $ua;
	$ua = new LWP::UserAgent;
	$ua->agent('Webcomics parser/0.1'); ### TODO: Id number
	return $ua;
    }
}

true;
