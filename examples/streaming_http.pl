#
# This example demonstrates progress notifications for a long-running MCP tool
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
use Mojo::IOLoop;
use Mojo::Promise;

my $server = MCP::Server->new;
$server->tool(
  name         => 'process_items',
  description  => 'Process a number of items and report progress along the way',
  input_schema => {type => 'object', properties => {items => {type => 'integer'}}},
  code         => sub ($tool, $args) {
    my $context = $tool->context;
    my $total   = $args->{items} || 5;
    my $promise = Mojo::Promise->new;
    my $done    = 0;
    my $id;
    $id = Mojo::IOLoop->recurring(
      0.5 => sub {
        $done++;
        $context->notify_progress($done, $total, "Processed item $done of $total");
        return if $done < $total;
        Mojo::IOLoop->remove($id);
        $promise->resolve("Processed $total items");
      }
    );
    return $promise;
  }
);

any '/mcp' => $server->to_action({streaming => 1});

app->start;
