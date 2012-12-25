package WWW::Webcomic::Page;

use strict;
use warnings;
no warnings qw(uninitialized);
our $VERSION = '0.02';

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::LazyRequire;

use URI;
use LWP::UserAgent;

class_type 'URI', { class => 'URI' };
coerce 'URI', from 'Str', via {
    URI->new($_);
};
has 'url' => (
    is            => 'ro',
    isa           => 'URI',
    coerce        => 1,
    lazy_required => 1,
);

has 'user_agent' => (
    is => 'ro',
    isa => 'LWP::UserAgent',
    builder => 'build_user_agent',
);

sub build_user_agent {
    my ($self) = @_;

    my $user_agent = LWP::UserAgent->new;
    $user_agent->agent($self->agent_string);
    return $user_agent;
}

sub agent_string {
    'Webcomics parser/' . $VERSION;
}

sub fetch_page {
    my ($self) = @_;

    my $response = $self->user_agent->get($self->url);
    if (!$response->is_success) {
        die "Couldn't fetch $self->url: ", $response->status_line;
    }
    return $response->decoded_content // $response->content;
    
}

__PACKAGE__->meta->make_immutable;
1;