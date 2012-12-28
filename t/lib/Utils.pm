# Various test stuff we need in multiple places.
package Utils;

use strict;
use warnings;
no warnings qw(uninitialized);
use parent qw(Exporter);

our @EXPORT = qw(_directory_is_safe);

use Test::More;

sub _directory_is_safe {
    my ($dir, $name) = @_;

    ok(
        !-e $dir || -e _ && -d _ && -w _,
        "$name $dir is safe to use or create"
    ) or exit;

    if (!-e $dir) {
        ok(mkdir($dir, 0755), "We can create our $name") or exit;
    }
}

