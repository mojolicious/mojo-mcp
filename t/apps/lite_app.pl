use Mojolicious::Lite -signatures;

use Mojo::MCP::Server;

my $server = Mojo::MCP::Server->new;
$server->tool(
  name         => 'echo',
  description  => 'Echo the input text',
  input_schema => {type => 'object', properties => {test => {type => 'string'}}, required => ['test']},
  code         => sub ($tool, $args) {
    return "Echo: $args->{test}";
  }
);

any '/mcp' => $server->to_action;

get '/' => {text => 'Hello MCP!'};

app->start;
