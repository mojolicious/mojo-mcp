use Mojolicious::Lite -signatures;

use MCP::Server;
use Mojo::IOLoop;
use Mojo::Promise;

my $server = MCP::Server->new;
$server->tool(
  name         => 'echo',
  description  => 'Echo the input text',
  input_schema => {type => 'object', properties => {test => {type => 'string'}}, required => ['test']},
  code         => sub ($tool, $args) {
    return "Echo: $args->{test}";
  }
);
$server->tool(
  name         => 'echo_async',
  description  => 'Echo the input text asynchronously',
  input_schema => {type => 'object', properties => {test => {type => 'string'}}, required => ['test']},
  code         => sub ($tool, $args) {
    my $promise = Mojo::Promise->new;
    Mojo::IOLoop->timer(0.5 => sub { $promise->resolve("Echo (async): $args->{test}") });
    return $promise;
  }
);

any '/mcp' => $server->to_action;

get '/' => {text => 'Hello MCP!'};

app->start;
