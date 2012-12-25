package WWW::Webcomic::Page;

use strict;
use warnings;
no warnings qw(uninitialized);
use vars qw($VERSION);

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::LazyRequire;

use HTML::TreeBuilder;
use URI;
use LWP::UserAgent;

=head1 NAME

WWW::Webcomic::Page - a webcomic page object

=head1 SYNOPSIS

 my $page = WWW::Webcomic::Page->new(url => 'http://xkcd.com/');
 my $contents = $page->contents;

=head1 DESCRIPTION

This is a Moose class that represents a webcomic page.

=head2 Attributes

=over

=item url

The URL of the page. Specify either a string or a URI object. Stored
internally as a URI object.

=cut

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

=item user_agent

The user-agent used to fetch pages. By default a standard LWP::UserAgent
object with a custom agent string to avoid some websites blocking
vanilla LWP.

=cut

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

=item contents

The contents of the page. Lazy, so only retrieved when first requested,
and cached for later use. Will die on errors, so be sure to wrap in
an eval block or Try::Tiny::catch etc.

=cut

has 'contents' => (
    is         => 'ro',
    isa        => 'Str',
    lazy_build => 1,
);

sub _build_contents {
    my ($self) = @_;

    $self->fetch_page;
}

sub fetch_page {
    my ($self) = @_;

    my $response = $self->user_agent->get($self->url);
    if (!$response->is_success) {
        die "Couldn't fetch $self->url: ", $response->status_line;
    }
    return $response->decoded_content // $response->content;    
}

=item tree

An HTML::TreeBuilder object of the fetched page. Like L<contents>, lazy,
so if you haven't explicitly fetched the page yet, be ready for exceptions.
Deleted when the object goes out of scope, so you don't have to worry about
cleaning up explicitly.

=cut

has 'tree' => (
    is => 'ro',
    isa => 'HTML::TreeBuilder',
    lazy_build => 1,
);

sub _build_tree {
    my ($self) = @_;

    my $tree = HTML::TreeBuilder->new;
    $tree->parse($self->contents);
    return $tree;
}

# This is Moose's version of DESTROY. DESTROY works as well, but you get
# warnings that Moose didn't override the standard DESTROY method which
# we can do without.

sub DEMOLISH {
    my ($self) = @_;

    if ($self->has_tree) {
        $self->tree->delete;
    }
}

=back

=head1 VERSION

This is version 0.02.

=cut

$VERSION = '0.02';

__PACKAGE__->meta->make_immutable;
1;