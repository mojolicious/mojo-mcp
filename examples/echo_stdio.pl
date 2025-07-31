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
use Mojo::Base -strict, -signatures;

use MCP::Server;

my $server = MCP::Server->new;
$server->tool(
  name         => 'echo',
  description  => 'Echo the input text',
  input_schema => {type => 'object', properties => {test => {type => 'string'}}, required => ['test']},
  code         => sub ($tool, $args) {
    return "Echo: $args->{test}";
  }
);

$server->to_stdio;
