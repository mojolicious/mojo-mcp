use Mojo::Base -strict, -signatures;

use Test::More;

use Mojolicious::Lite;
use Test::Mojo;
use MCP::Client;
use MCP::Constants qw(META_SUBSCRIPTION_ID PROTOCOL_VERSION);
use MCP::Server;
use Mojo::IOLoop;
use Mojo::JSON qw(true);
use Mojo::Promise;

my $server = MCP::Server->new;

$server->tool(
  name => 'echo',
  code => sub ($tool, $args) {
    return 'echo';
  }
);
$server->prompt(
  name => 'plan',
  code => sub ($prompt, $args) {
    return 'plan';
  }
);
$server->resource(
  uri  => 'file:///report',
  code => sub ($resource) {
    return 'report';
  }
);

any '/mcp' => $server->to_action({streaming => 1, heartbeat => 0});

my $t      = Test::Mojo->new;
my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));

sub settle ($delay = 0.1) {
  my $tick = Mojo::Promise->new;
  Mojo::IOLoop->timer($delay => sub { $tick->resolve });
  return $tick->wait;
}

subtest 'Discovery' => sub {
  my $caps = $client->discover->{capabilities};
  is $caps->{prompts}{listChanged},   true, 'prompts listChanged advertised';
  is $caps->{resources}{listChanged}, true, 'resources listChanged advertised';
  is $caps->{tools}{listChanged},     true, 'tools listChanged advertised';
};

subtest 'Other methods' => sub {
  $t->get_ok('/mcp')->status_is(405)->json_is('/error' => 'Method not allowed');
  $t->delete_ok('/mcp')->status_is(405)->json_is('/error' => 'Method not allowed');
};

subtest 'List changed' => sub {
  my @messages;
  ok $client->listen(
    {promptsListChanged => true, resourceSubscriptions => true, toolsListChanged => true},
    sub ($message) {
      push @messages, $message;
      if (@messages == 1) {
        $server->notify_list_changed('resources');
        $server->notify_list_changed('prompts');
      }
      return @messages < 2;
    }
    ),
    'stream closed by callback';

  my $ack = $messages[0];
  is $ack->{jsonrpc}, '2.0',                                      'JSON-RPC version';
  is $ack->{method},  'notifications/subscriptions/acknowledged', 'acknowledged first';
  is_deeply $ack->{params}{notifications}, {promptsListChanged => true, toolsListChanged => true},
    'unsupported notification types dropped';
  ok my $id = $ack->{params}{_meta}{+META_SUBSCRIPTION_ID}, 'subscription id';

  my $changed = $messages[1];
  is $changed->{method}, 'notifications/prompts/list_changed', 'unsubscribed type never delivered';
  is $changed->{params}{_meta}{+META_SUBSCRIPTION_ID}, $id,    'subscription id';
  is scalar @messages,                                 2,      'no more messages';
};

subtest 'List changed (no subscriptions)' => sub {
  settle;
  is_deeply $server->transport->subscriptions, {}, 'subscription removed on disconnect';
  ok $server->notify_list_changed('tools'), 'broadcast attempted';
};

subtest 'Heartbeat' => sub {
  my $transport = $server->transport;
  $transport->heartbeat(0.1);

  my $request = $client->build_request('subscriptions/listen', {notifications => {toolsListChanged => true}});
  my $headers = {
    Accept                 => 'text/event-stream',
    'MCP-Protocol-Version' => PROTOCOL_VERSION,
    'Mcp-Method'           => 'subscriptions/listen'
  };
  my $tx = $t->ua->build_tx(POST => $t->ua->server->url->path('/mcp') => $headers => json => $request);
  $t->ua->start_p($tx)->catch(sub { });
  Mojo::IOLoop->one_tick until $tx->res->code || $tx->error;
  is $tx->res->code,                  200,                 'stream open';
  is $tx->res->headers->content_type, 'text/event-stream', 'right content type';

  # SSE parser strips comments
  my $bytes = '';
  Mojo::IOLoop->stream($tx->connection)->on(read => sub ($stream, $chunk) { $bytes .= $chunk });
  settle 0.5;
  like $bytes, qr/: keepalive/, 'heartbeat sent';

  Mojo::IOLoop->remove($tx->connection);
  $transport->heartbeat(0);
  settle;
  is_deeply $transport->subscriptions, {}, 'subscription removed on disconnect';
};

done_testing;
