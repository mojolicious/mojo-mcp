use Mojolicious::Lite -signatures;

use MCP::Server;
use Mojo::IOLoop;
use Mojo::Promise;
use Mojo::File qw(curfile);

my $server = MCP::Server->new;
$server->tool(
  name         => 'echo',
  description  => 'Echo the input text',
  input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
  code         => sub ($tool, $args) {
    return "Echo: $args->{msg}";
  }
);
$server->tool(
  name         => 'echo_async',
  description  => 'Echo the input text asynchronously',
  input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
  code         => sub ($tool, $args) {
    my $promise = Mojo::Promise->new;
    Mojo::IOLoop->timer(0.5 => sub { $promise->resolve("Echo (async): $args->{msg}") });
    return $promise;
  }
);
$server->tool(
  name         => 'echo_header',
  description  => 'Echo the input text with a header',
  input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
  code         => sub ($tool, $args) {
    my $context = $tool->context;
    my $header  = $context->{controller}->req->headers->header('Mcp-Custom-Header');
    return "Echo with header: $args->{msg} (Header: $header)";
  }
);
$server->tool(
  name        => 'time',
  description => 'Get the current time in epoch format',
  code        => sub ($tool, $args) {
    return time;
  }
);
$server->tool(
  name         => 'generate_image',
  description  => 'Generate a simple image from text',
  input_schema => {type => 'object', properties => {text => {type => 'string'}}, required => ['text']},
  code         => sub ($tool, $args) {
    my $image = curfile->sibling('mojolicious.png')->slurp;
    return $tool->image_result($image, {annotations => {audience => ['user']}});
  }
);

any '/mcp' => $server->to_action;

get '/' => {text => 'Hello MCP!'};

app->start;
