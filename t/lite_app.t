use Mojo::Base -strict;

use Test::More;

use Test::Mojo;
use Mojo::File qw(curfile);

my $t = Test::Mojo->new(curfile->sibling('apps', 'lite_app.pl'));

$t->get_ok('/')->status_is(200)->content_like(qr/Hello MCP!/);

done_testing;
