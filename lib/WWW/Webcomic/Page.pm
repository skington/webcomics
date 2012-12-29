package WWW::Webcomic::Page;

use strict;
use warnings;
no warnings qw(uninitialized);
use vars qw($VERSION);
use English qw(-no_match_vars);
use Encode;

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

    return $self->_file_path_for_uri($self->url);
}

sub _file_path_for_uri {
    my ($self, $uri) = @_;

    my @components = $self->_cached_file_components($uri);
    my $target_directory = $self->cache_directory;
    sub_directory:
    while (@components > 1) {
        my $sub_directory = shift @components;
        ### TODO: cope with Windows.
        $target_directory .= '/' . $sub_directory;
        if (-e $target_directory && -d _ && -w _) {
            next sub_directory;
        }
        mkdir($target_directory, 0755)
            or die "Couldn't create $target_directory: $!";
    }
    return $target_directory . '/' . (shift @components || 'index.html');
}

sub _cached_file_components {
    my ($self, $uri) = @_;

    my @components = ($uri->host);
    if (length($uri->path)) {
        my @path_components = split('/', $uri->path);
        shift @path_components;
        push @components, @path_components;
        if ($uri->path =~ m{ / $ }x) {
            push @components, 'index.html';
        }
    }
    if ($uri->query) {
        $components[-1] .= '?' . $uri->query;
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
        if (my $cached_contents = $self->_fetch_cached_contents) {
            return $cached_contents;
        }
    }
    return $self->_fetch_page;
}

sub _fetch_cached_contents {
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

sub _fetch_page {
    my ($self) = @_;

    # Fetch the page.
    my $response = $self->user_agent->get($self->url);
    if (!$response->is_success) {
        die "Couldn't fetch $self->url: ", $response->status_line;
    }

    # Work out its contents, and cache them if necessary.
    # If this looks like a redirect, make a symlink from the requested
    # URL to the stored URL.
    my $contents = $response->decoded_content // $response->content;
    if ($self->has_cache_directory) {
        $self->_store_cached_contents($response->request->uri, $contents);
        if ($response->request->uri->as_string ne $self->url->as_string) {
            my $stored_file
                = $self->_file_path_for_uri($response->request->uri);
            my $requested_file = $self->_file_path_for_uri($self->url);
            if (!-e $requested_file) {
                symlink($stored_file, $requested_file)
                    or carp "Couldn't link $requested_file to $stored_file: "
                    . $OS_ERROR;
            }
        }
    }

    # And return the result.
    return $contents;
}

sub _store_cached_contents {
    my ($self, $uri, $contents) = @_;

    my $file_path = $self->_file_path_for_uri($uri);
    open(my $fh, '>', $file_path) or do {
        carp sprintf(q{Couldn't write %s to cached file %s: %s'},
            $uri->as_string, $file_path, $OS_ERROR);
        return;
    };
    print $fh Encode::encode('UTF-8', $contents);
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