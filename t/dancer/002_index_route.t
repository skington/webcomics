use Test::More tests => 2;
use common::sense;
use lib::abs qw(../../lib);

# the order is important
use webcomics;
use Dancer::Test;

route_exists [GET => '/'], 'a route handler is defined for /';

### TODO: get config working properly
#response_status_is ['GET' => '/'], 200, 'response status is 200 for /';
