#
# This example demonstrates a simple MCP server using stdio
#
# mcp.json:
# {
#   "mcpServers": {
#     "mojo": {
#       "command": "/home/kraih/mojo-mcp/examples/echo_stdio.pl"
#     }
#   }
# }
#
use Mojo::MCP::Server;

my $server = Mojo::MCP::Server->new;
$server->tool(
  name         => 'echo',
  description  => 'Echo the input text',
  input_schema => {type => 'object', properties => {test => {type => 'string'}}, required => ['test']},
  code         => sub ($args) {
    return "Echo: $args->{test}";
  }
);

$server->to_stdio;
