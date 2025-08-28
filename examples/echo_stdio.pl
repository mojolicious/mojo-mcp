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
  input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
  code         => sub ($tool, $args) {
    return "Echo: $args->{msg}";
  }
);
$server->prompt(
  name        => 'echo',
  description => 'A prompt to demonstrate the echo tool',
  code        => sub ($prompt, $args) {
    return 'Use the echo tool with the message "Hello, World!"';
  }
);

$server->to_stdio;
