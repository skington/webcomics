package WWW::Webcomic::Page;

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

=item cache_directory

Optional; a directory where web pages are stored.

If a cache directory is set, and a request is made for a page that is stored
in the cache, the cache will be used.

If a cache directory is set, and a request is made for a page that is not
stored in the cache, the page contents will be stored in the cache.

If cache_directory is /tmp/cache, http://example.com/ will be stored in
/tmp/cache/example.com/index.html and http://example.com/foo/bar/baz.gif
will be stored in /tmp/cache/example.com/foo/bar/baz.gif

No distinction is made between http and https, or any other URL protocols.

=cut

has 'cache_directory' => (
    is        => 'rw',
    isa       => 'WWW::Webcomic::CacheDir',
    predicate => 'has_cache_directory',
);

=item cached_file_path

The full filesystem path of the file where the page would be stored.
Undef if there is no cache_directory.

Lazy attribute; will create the requisite subdirectories, or die trying,
when called.

=cut

has 'cached_file_path' => (
    is         => 'ro',
    isa        => 'Str',
    lazy_build => 1,
);

sub _build_cached_file_path {
    my ($self) = @_;

    return if !$self->has_cache_directory;

    my @components = $self->_cached_file_components;
    my $target_directory = $self->cache_directory;
    sub_directory:
    while (@components > 1) {
        my $sub_directory = shift @components;
        ### TODO: cope with Windows.
        $target_directory .= '/' . $sub_directory;
        if (-e $target_directory && -d _ && -w _) {
            next sub_directory;
        } elsif (-e $target_directory) {
            1;
        }
        mkdir($target_directory, 0755) or do {
            1;
        }
            or die "Couldn't create $target_directory: $!";
    }
    return $target_directory . '/' . (shift @components || 'index.html');
}

sub _cached_file_components {
    my ($self) = @_;
    
    my @components = ($self->url->host);
    if (length($self->url->path)) {
        my @path_components = split('/', $self->url->path);
        shift @path_components;
        push @components, @path_components;
        if ($self->url->path =~ m{ / $ }x) {
            push @components, 'index.html';
        }
    }
    if ($self->url->query) {
        $components[-1] .= '?' . $self->url->query;
    }
    return @components;
}


=item contents

The contents of the page. Lazy, so only retrieved when first requested,
and cached in memory for later use. Will die on errors, so be sure to wrap in
an eval block or Try::Tiny::catch etc.

=cut

has 'contents' => (
    is         => 'ro',
    isa        => 'Str',
    lazy_build => 1,
);

sub _build_contents {
    my ($self) = @_;

    if ($self->has_cache_directory) {
        if (my $cached_contents = $self->fetch_cached_contents) {
            return $cached_contents;
        }
    }
    my $contents = $self->fetch_page;
    if ($self->has_cache_directory) {
        $self->store_cached_contents($contents);
    }
    return $contents;
}

sub fetch_cached_contents {
    my ($self) = @_;

    # It's OK not to have a cached file.
    return if !-e $self->cached_file_path;

    # But we should squawk if it doesn't exist.
    open(my $fh, '<', $self->cached_file_path)
        or die sprintf(q{Couldn't open cached %s as %s: %s},
        $self->url, $self->cached_file_path, $OS_ERROR);

    # Slurp the contents in and return them.
    local $INPUT_RECORD_SEPARATOR = undef;
    my $contents = <$fh>;
    close $fh;

    return $contents;
}

sub fetch_page {
    my ($self) = @_;

    my $response = $self->user_agent->get($self->url);
    if (!$response->is_success) {
        die "Couldn't fetch $self->url: ", $response->status_line;
    }
    return $response->decoded_content // $response->content;    
}

sub store_cached_contents {
    my ($self, $contents) = @_;

    open(my $fh, '>', $self->cached_file_path) or do {
        carp sprintf(q{Couldn't write %s to cached file %s: %s'},
            $self->url, $self->cached_file_path, $OS_ERROR);
        return;
    };
    print $fh $contents;
    close $fh;
    return;
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