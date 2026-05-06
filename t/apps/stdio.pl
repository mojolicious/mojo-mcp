use Mojo::Base -strict, -signatures;

use MCP::Server;
use Mojo::IOLoop;
use Mojo::Promise;

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
  name         => 'echo_log',
  description  => 'Echo the input text and log a notification',
  input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
  code         => sub ($tool, $args) {
    $tool->notify('notifications/message', {level => 'info', data => $args->{msg}});
    return "Echo: $args->{msg}";
  }
);
$server->tool(
  name        => 'reload',
  description => 'Broadcast a tools list_changed notification',
  code        => sub ($tool, $args) {
    $server->notify_list_changed('tools');
    return 'reloaded';
  }
);

$server->to_stdio;
