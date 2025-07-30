use Mojo::Base -strict, -signatures;

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

$server->to_stdio;
