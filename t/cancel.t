use Mojo::Base -strict, -signatures;

use Test::More;

use Mojolicious::Lite;
use Test::Mojo;
use MCP::Constants qw(META_CLIENT_CAPABILITIES META_PROTOCOL_VERSION PROTOCOL_VERSION);
use MCP::Server;
use Mojo::IOLoop;
use Mojo::JSON qw(from_json);
use Mojo::Promise;

my $server = MCP::Server->new;

my $observed = {};
$server->tool(
  name => 'slow',
  code => sub ($tool, $args) {
    my $context = $tool->context;
    my $promise = Mojo::Promise->new;
    my $id      = Mojo::IOLoop->recurring(0.05 => sub { $context->notify_progress(1, 2, 'working') });

    $observed = {cancelled => 0, before => $context->is_cancelled};
    $context->on(
      cancelled => sub ($context) {
        Mojo::IOLoop->remove($id);
        $observed->{cancelled}++;
        $observed->{after}  = $context->is_cancelled;
        $observed->{notify} = $context->notify('notifications/message', {data => 'too late'});
        $promise->resolve('finished');
      }
    );

    $context->notify_progress(0, 2, 'starting');
    return $promise;
  }
);

any '/mcp' => $server->to_action;

my $t = Test::Mojo->new;

subtest 'Cancellation by closing the response stream' => sub {
  my $meta = {META_CLIENT_CAPABILITIES() => {}, META_PROTOCOL_VERSION() => PROTOCOL_VERSION, progressToken => 'p1'};
  my $body
    = {jsonrpc => '2.0', id => 1, method => 'tools/call', params => {name => 'slow', arguments => {}, _meta => $meta}};
  my $headers = {
    Accept                 => 'text/event-stream',
    'MCP-Protocol-Version' => PROTOCOL_VERSION,
    'Mcp-Method'           => 'tools/call',
    'Mcp-Name'             => 'slow'
  };

  my @messages;
  my $tx = $t->ua->build_tx(POST => $t->ua->server->url->path('/mcp') => $headers => json => $body);
  $tx->res->content->on(
    sse => sub ($content, $event = undef) {
      return unless $event && $event->{text};
      push @messages, from_json($event->{text});
      Mojo::IOLoop->remove($tx->connection);
    }
  );
  $t->ua->start_p($tx)->catch(sub { });
  Mojo::IOLoop->one_tick until $tx->is_finished || $tx->error;

  is $tx->res->code,                                 200,                      'stream open';
  is $tx->res->headers->content_type,                'text/event-stream',      'right content type';
  is $tx->res->headers->header('X-Accel-Buffering'), 'no',                     'buffering disabled';
  is scalar @messages,                               1,                        'nothing written after the client left';
  is $messages[0]{method},                           'notifications/progress', 'buffered notification flushed';
  is $messages[0]{params}{message},                  'starting',               'progress message';

  my $tick = Mojo::Promise->new;
  Mojo::IOLoop->timer(0.2 => sub { $tick->resolve });
  $tick->wait;

  is $observed->{before},    0,     'not cancelled while running';
  is $observed->{cancelled}, 1,     'cancelled event emitted once';
  is $observed->{after},     1,     'cancelled afterwards';
  is $observed->{notify},    undef, 'notifications declined after cancellation';
};

done_testing;
