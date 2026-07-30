package MCP;
use Mojo::Base -base, -signatures;

our $VERSION = '0.15';

1;

=encoding utf8

=head1 NAME

MCP - Model Context Protocol Perl SDK

=head1 SYNOPSIS

  use Mojolicious::Lite -signatures;

  use MCP::Server;

  my $server = MCP::Server->new;
  $server->tool(
    name        => 'time',
    description => 'Get the current local time',
    code        => sub ($tool, $args) {
      return localtime(time);
    }
  );

  any '/mcp' => $server->to_action;

  app->start;

=head1 DESCRIPTION

Connect Perl with AI using the Model Context Protocol (MCP). An MCP server hands a model three kinds of things:
L<tools|MCP::Tool> it can call, L<prompts|MCP::Prompt> it can start from, and L<resources|MCP::Resource> it can read.
At its core MCP is all about text processing, which makes it a great fit for Perl.

The protocol revision implemented is C<2026-07-28>, and it is stateless. There is no handshake and no session, every
request stands on its own, so an MCP endpoint is just another route in your L<Mojolicious> application and scales
the same way.

Read on for a tour, or go straight to L<MCP::Server> for the reference documentation.

=head1 TUTORIAL

A walk through building MCP applications with Perl, from a single tool to a deployed web service.

=head2 Concepts

A server exposes three kinds of primitives, and you can mix them freely.

  # Called by the model, whenever it decides to
  $server->tool(name => 'deploy', code => sub ($tool, $args) {...});

  # Picked by the user, usually from a menu
  $server->prompt(name => 'review', code => sub ($prompt, $args) {...});

  # Read by the client, to put into context
  $server->resource(uri => 'file:///readme', code => sub ($resource) {...});

L<Tools|MCP::Tool> are functions the model calls on its own, and are what most servers are made of.
L<Prompts|MCP::Prompt> are templates a user invokes deliberately. L<Resources|MCP::Resource> are documents a client
attaches to a conversation. Everything else in this tutorial builds on those three.

=head2 Your first server

This is a complete MCP server that gives a model access to your local Perl documentation.

  use Mojo::Base -strict, -signatures;

  use MCP::Server;

  my $server = MCP::Server->new(name => 'PerldocServer');

  $server->tool(
    name         => 'perldoc',
    description  => 'Look up the documentation of a Perl module',
    input_schema => {
      type       => 'object',
      properties => {module => {type => 'string', description => 'Module name, such as Mojo::UserAgent'}},
      required   => ['module']
    },
    code => sub ($tool, $args) {
      my $module = $args->{module};
      return $tool->text_result("Not a module name: $module", 1) unless $module =~ /^\w+(?:::\w+)*\z/;
      open my $doc, '-|', 'perldoc', '-o', 'text', '-T', $module or return $tool->text_result('Found no perldoc', 1);
      my $text = do { local $/; <$doc> };
      return length($text // '') ? $text : $tool->text_result("Found no documentation for $module", 1);
    }
  );

  $server->to_stdio;

The name and description are how a model decides to call the tool, so write them for the model rather than for a
human reader. The L<input schema|MCP::Tool/"input_schema"> is enforced before your code runs, so C<$args> is always
valid by the time you see it. Returning a plain string is shorthand for a text result.

=head2 Talking to your server

L<MCP::Server/"to_stdio"> speaks JSON-RPC on standard input and output, so you can drive the server by hand. Every
request declares the protocol version it was made with and the capabilities of the client making it.

  $ perl perldoc_stdio.pl
  {"jsonrpc":"2.0","id":1,"method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}
  {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"perldoc","arguments":{"module":"Mojo::JSON"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}

One JSON object per line, in and out. That is the whole protocol, and it is worth doing once before reaching for a
client.

=head2 Connecting a client

Most MCP hosts launch stdio servers themselves and are configured with a JSON file, C<claude_desktop_config.json>
for Claude Desktop and C<mcp.json> for many others.

  {
    "mcpServers": {
      "perldoc": {
        "command": "perl",
        "args": ["/absolute/path/to/perldoc_stdio.pl"]
      }
    }
  }

Use absolute paths, since the host does not run the command from your working directory, and restart the host to
pick up changes. When a server does not show up, its C<STDERR> is where to look, see L</"Logging">.

=head2 Web applications

The same server becomes an HTTP endpoint with L<MCP::Server/"to_action">, which returns a plain L<Mojolicious>
action.

  use Mojolicious::Lite -signatures;

  use MCP::Server;

  my $server = MCP::Server->new(name => 'PerldocServer');
  $server->tool(...);

  any '/mcp' => $server->to_action;

  app->start;

There is nothing special about that route. It can sit under an C<under>, carry placeholders, or share authentication
with the rest of your application. In a full L<Mojolicious> application it goes into C<startup> like any other.

  sub startup ($self) {
    my $server = MCP::Server->new(name => 'PerldocServer');
    $server->tool(...);
    $self->routes->any('/mcp' => $server->to_action);
  }

Clients reach it with the Streamable HTTP transport, so the same JSON travels in a C<POST> body.

  {
    "mcpServers": {
      "perldoc": {
        "url": "http://127.0.0.1:3000/mcp"
      }
    }
  }

=head2 Testing

L<MCP::Client> is conformant on the wire, so pointing it at a L<Test::Mojo> application tests a server the way a real
client sees it.

  use Mojo::Base -strict, -signatures;

  use Test::More;
  use Test::Mojo;
  use MCP::Client;

  my $t      = Test::Mojo->new('MyApp');
  my $client = MCP::Client->new(ua => $t->ua, url => $t->ua->server->url->path('/mcp'));

  my $result = $client->call_tool('perldoc', {module => 'Mojo::JSON'});
  like $result->{content}[0]{text}, qr/Minimalistic JSON/, 'documentation found';

  done_testing;

Sharing the user agent with L<Test::Mojo> keeps requests inside the process, so no port is ever bound.

=head2 Validating arguments

Input schemas are JSON Schema 2020-12 unless they name another dialect with C<$schema>, and are checked before your
code is reached, so a call with bad arguments never becomes your problem.

  use Mojo::JSON qw(false);

  input_schema => {
    type       => 'object',
    properties => {
      module => {type => 'string', description => 'Module name, such as Mojo::UserAgent'},
      lines  => {type => 'integer', description => 'Maximum number of lines', minimum => 1, maximum => 500}
    },
    required             => ['module'],
    additionalProperties => false
  }

Descriptions are part of the interface, since the model reads them to decide what to pass, and so are the
constraints. A schema that says up front what is acceptable produces fewer failed calls than a tool that says so
afterwards.

=head2 Tool results

Returning a string is shorthand for L<MCP::Tool/"text_result">, and there are constructors for the other content
types.

  # Text
  return $tool->text_result('Hello!');

  # Error the model can see and react to
  return $tool->text_result("Found no documentation for $module", 1);

  # Image or audio bytes, base64 encoded for you
  return $tool->image_result($png, {mime_type => 'image/png'});
  return $tool->audio_result($wav);

  # Pointer to a resource, instead of its content
  return $tool->resource_link_result('file:///perl/config', {name => 'perl_config'});

Anything the model could react to belongs in the result with the error flag set, such as a name that does not exist
or an argument that makes no sense together with another. A tool that dies is answered with an C<InternalError>
instead, and the exception goes to L<MCP::Server/"log"> rather than to the caller, since it can easily contain file
system paths or connection strings. That is a safe fallback and a poor error message, so prefer returning an error
result for anything you can predict.

=head2 Structured results

A tool with an L<output schema|MCP::Tool/"output_schema"> returns data instead of prose, and the client gets a
guarantee about its shape.

  $server->tool(
    name          => 'perl_version',
    description   => 'Version of the Perl interpreter running this server',
    output_schema => {
      type       => 'object',
      properties => {version => {type => 'string'}, release => {type => 'number'}},
      required   => ['version', 'release']
    },
    code => sub ($tool, $args) {
      return $tool->structured_result({version => "$^V", release => $] + 0});
    }
  );

Structured content is validated against the output schema before it is sent, and data that does not match becomes an
error result, so a tool cannot quietly break its own contract.

=head2 Prompts

Prompts are templates a user picks deliberately, usually from a menu in the client.

  $server->prompt(
    name        => 'explain',
    description => 'Explain what a Perl module is for',
    arguments   => [{name => 'module', description => 'Module name', required => 1}],
    code        => sub ($prompt, $args) {
      return "Read the documentation of $args->{module} with the perldoc tool, then explain in three sentences "
        . 'what problem it solves and when to reach for it.';
    }
  );

A plain string becomes a user message, and L<MCP::Prompt/"text_prompt"> gives you control over the role.

  return $prompt->text_prompt('You are a Perl mentor.', 'assistant');

=head2 Resources

Resources are documents a client can read and attach to a conversation, identified by URI.

  use Config;

  $server->resource(
    uri         => 'file:///perl/config',
    name        => 'perl_config',
    description => 'Configuration of the Perl interpreter running this server',
    mime_type   => 'text/plain',
    code        => sub ($resource) {
      return join "\n", map {"$_=$Config{$_}"} qw(archname osname perlpath version);
    }
  );

Resources take no arguments, only the URI they were registered with. For binary content use
L<MCP::Resource/"binary_resource">, which base64 encodes it for you.

=head2 Non-blocking tools

A tool that returns a L<Mojo::Promise> leaves the server free to handle other requests while it waits, which starts
to matter as soon as it talks to the network.

  use Mojo::URL;
  use Mojo::UserAgent;

  my $ua = Mojo::UserAgent->new;

  $server->tool(
    name         => 'metacpan',
    description  => 'Look up the latest release of a distribution on MetaCPAN',
    input_schema => {type => 'object', properties => {dist => {type => 'string'}}, required => ['dist']},
    code         => sub ($tool, $args) {
      my $url = Mojo::URL->new('https://fastapi.metacpan.org/v1/release');
      push @{$url->path->parts}, $args->{dist};

      return $ua->get_p($url)->then(sub ($tx) {
        my $release = $tx->result->json;
        return "$release->{name} was released on $release->{date} by $release->{author}";
      })->catch(sub ($err) {
        return $tool->text_result("MetaCPAN is unavailable: $err", 1);
      });
    }
  );

The promise resolves to whatever a synchronous tool would have returned. Both transports serve other requests while
it is pending.

Two details are worth copying. The argument becomes a path part instead of being interpolated into the URL, so a
value containing a slash or a question mark cannot change which endpoint is called. And the chain ends in a
C<catch>, which turns a failure into an error result; a promise that is rejected instead never produces a response
at all.

=head2 Progress reports

Long running tools report progress through the L<context|MCP::Server::Context>, the per-request object your code
shares with the transport.

  code => sub ($tool, $args) {
    my $context = $tool->context;

    my $total = @{$args->{modules}};
    my $done  = 0;
    for my $module (@{$args->{modules}}) {
      $context->notify_progress(++$done, $total, "Indexed $module");
      ...
    }

    return "Indexed $total modules";
  }

Notifications travel on the response stream of the request they belong to, which is upgraded from JSON to SSE the
moment there is something to send. That needs no configuration and works behind a pre-forking web server.

Capture the context in a variable before an async boundary, since L<MCP::Primitive/"context"> is only valid for the
duration of the call itself.

  code => sub ($tool, $args) {
    my $context = $tool->context;
    my $promise = Mojo::Promise->new;
    Mojo::IOLoop->timer(1 => sub {
      $context->notify_progress(1, 1, 'Finished');
      $promise->resolve('Done');
    });
    return $promise;
  }

Progress is only sent when the client asked for it with a progress token, so C<notify_progress> is always safe to
call.

=head2 Logging

L<MCP::Server::Context/"notify_log"> sends log messages to the client, gated by the level it asked for.

  $context->notify_log(info    => "Looking up $module");
  $context->notify_log(warning => {module => $module, truncated => 1});

Nothing is sent unless the client requested logging for the current request, and messages below the level it asked
for are dropped, so this too is always safe to call.

Your own logs belong on C<STDERR>, which is where L<Mojo::Log> writes and where an MCP host collects them. Never
write to C<STDOUT> from a stdio server, because that is the JSON-RPC channel and a stray C<print> corrupts it.

  # Bad, breaks the stdio transport
  print "Looking up $module\n";

  # Good
  my $log = Mojo::Log->new;
  $log->info("Looking up $module");

=head2 Cancellation

When a client goes away the context emits L<MCP::Server::Context/"cancelled">, so work can stop instead of running
to completion for nobody.

  code => sub ($tool, $args) {
    my $context = $tool->context;
    my $promise = Mojo::Promise->new;
    my $id      = Mojo::IOLoop->recurring(1 => sub {...});
    $context->on(cancelled => sub ($context) { Mojo::IOLoop->remove($id) });
    return $promise;
  }

Code that cannot subscribe to an event polls L<MCP::Server::Context/"is_cancelled"> instead. Both transports feed the
same signal, a closed response stream over HTTP and a C<notifications/cancelled> notification over stdio, so a tool
only has to handle it once.

=head2 Asking the client for input

A tool that needs a decision from the user returns an C<input_required> result instead of a final one, and the client
calls it again with the answer.

  $server->tool(
    name         => 'delete_release',
    input_schema => {type => 'object', properties => {name => {type => 'string'}}, required => ['name']},
    code         => sub ($tool, $args) {
      my $context = $tool->context;
      my $state   = $context->request_state;
      my $confirm = ($context->input_responses // {})->{confirm} // {};
      return $tool->text_result("Deleted $state->{name}") if $state && ($confirm->{action} // '') eq 'accept';

      return $tool->input_required({
        confirm => {
          method => 'elicitation/create',
          params => {
            message         => "Really delete $args->{name}?",
            requestedSchema => {type => 'object', properties => {ok => {type => 'boolean'}}}
          }
        }
      }, {name => $args->{name}});
    }
  );

The second argument is state carried across the round trip, and the server remembers nothing. It is sealed with
HMAC-SHA256, bound to the caller and to this very tool, and given a short lifetime, so a client cannot edit it on the
way back. L<MCP::Server::Context/"request_state"> returns C<undef> for state that fails any of those checks, which
your code should treat exactly like a first call and simply ask again.

Note that the retry acts on C<< $state->{name} >> and not on C<< $args->{name} >>. Only the state is sealed; the
arguments of the second call are as fresh and as untrusted as those of the first, so a client could ask about one
release and then present that confirmation with another one named. Whatever the user actually agreed to has to come
back out of the state.

Only ask for capabilities the client declared in L<MCP::Server::Context/"client_capabilities">, and set
L<MCP::Server/"state_secret"> if the server runs in more than one process, see L</"Deployment">.

=head2 Authentication and scopes

An MCP endpoint is authenticated like any other route, and for OAuth 2.0 bearer tokens the HTTP transport has an
L<auth hook|MCP::Server::Transport::HTTP/"auth"> that runs before dispatch.

  any '/mcp' => $server->to_action({
    auth => sub ($c) {
      return undef unless ($c->req->headers->authorization // '') =~ /^Bearer\s+(\S+)$/;
      return undef unless my $token = validate_token($1);
      $c->stash(role => $token->{role});
      return {principal => $token->{sub}, scopes => $token->{scopes}};
    },
    metadata_url => 'https://example.com/.well-known/oauth-protected-resource'
  });

Returning a false value rejects the request with a C<401> and a C<WWW-Authenticate> challenge pointing at the
metadata document. Validating the token is yours to do, since only your application knows the authorization server.

Primitives can then require scopes, which are checked on every call and hide the primitive from callers who are not
entitled to see it.

  $server->tool(name => 'delete_release', scopes => ['mcp:write'], code => sub ($tool, $args) {...});

Scopes are enforced against what the hook granted, so they only protect anything on a server that has one. Without
it no request carries scopes, and a scoped primitive is as reachable as an unscoped one; over stdio, where the
caller is whoever started the process, that is the intended behaviour.

Serve the metadata document with L<MCP::Server/"oauth_metadata">, which fills in the scopes your server actually
uses.

  get '/.well-known/oauth-protected-resource' => sub ($c) {
    $c->render(json => $server->oauth_metadata(
      resource              => 'https://example.com/mcp',
      authorization_servers => ['https://auth.example.com']
    ));
  };

=head2 Per-caller primitives

The lists of tools, prompts and resources are assembled per request, and L<MCP::Server> emits an event for each one,
so a single server can show different things to different callers.

  $server->on(tools => sub ($server, $tools, $context) {
    my $c = $context->controller;
    return if $c && ($c->stash('role') // '') eq 'admin';
    @$tools = grep { $_->name ne 'delete_release' } @$tools;
  });

The array reference is yours to modify in place, and removing a primitive also makes it uncallable, not merely
invisible. Everything known about the caller is on the L<context|MCP::Server::Context>, including the
L<Mojolicious::Controller> for HTTP requests, which is only there for the HTTP transport. Decide what to hide from
what the context actually says, never from what it fails to say, so an unauthenticated request ends up with the
smallest list rather than the largest.

=head2 Caching

Results that are expensive to produce and rarely change may be cached by clients and gateways, for as long as the
primitive says.

  $server->resource(uri => 'file:///perl/config', cache_ttl => 3_600_000, code => sub ($resource) {...});

Times are in milliseconds, and the default of C<0> means every result has to be revalidated. Lists derive their
hints from the primitives in them, and are marked C<private> as soon as they could differ per caller, which is the
case for every server using scopes or the events above, so caching never leaks one caller's view to another.

=head2 Notification streams

Notifications that belong to no request, such as a tool list that changed while a client was connected, need a
stream of their own. Clients open one with C<subscriptions/listen>, which has to be enabled explicitly.

  any '/mcp' => $server->to_action({streaming => 1});

  # Somewhere else in the application
  $server->notify_list_changed('tools');

Every subscription only receives the notification types it asked for. This is the one part of the protocol that
keeps per-process state, so it is off by default and not compatible with pre-forking web servers. Progress and log
notifications do not depend on it.

=head2 Deployment

An MCP endpoint deploys exactly like the rest of your L<Mojolicious> application, see
L<Mojolicious::Guides::Cookbook/"DEPLOYMENT">. The protocol is stateless, so a pre-forking web server and a load
balancer need no special handling.

  $ ./myapp.pl prefork

Serve a remote endpoint over HTTPS, which the protocol requires and which is usually the reverse proxy's job. Two
settings are worth having as well. L<MCP::Server/"state_secret"> has to be shared by every process that could serve
a retry, or state minted by one worker is rejected by the next, and L<MCP::Server::Transport::HTTP/"origins">
protects a server bound to localhost from being driven by a web page.

  my $server = MCP::Server->new(state_secret => $ENV{MCP_STATE_SECRET});

  any '/mcp' => $server->to_action({origins => ['https://example.com']});

Everything except L</"Notification streams"> works under C<prefork>.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2025-2026, Sebastian Riedel.

This program is free software, you can redistribute it and/or modify it under the terms of the MIT license.

=head1 SEE ALSO

L<MCP::Server>, L<MCP::Client>, L<Mojolicious>, L<https://mojolicious.org>, L<https://modelcontextprotocol.io>.

=cut
