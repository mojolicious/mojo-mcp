#
# This example demonstrates a streaming MCP server using Mojolicious
#
# mcp.json:
# {
#   "mcpServers": {
#     "mojo": {
#       "url": "http://127.0.0.1:3000/mcp"
#     }
#   }
# }
#
use Mojolicious::Lite -signatures;

use MCP::Server;

my $server = MCP::Server->new;
$server->tool(
  name         => 'echo',
  description  => 'Echo the input text',
  input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
  code         => sub ($tool, $args) {
    $tool->notify('notifications/message', {level => 'info', data => "Echoing: $args->{msg}"});
    return "Echo: $args->{msg}";
  }
);

any '/mcp' => $server->to_action({streaming => 1});

app->start;
