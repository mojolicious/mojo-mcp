
# MCP Perl SDK

 [![](https://github.com/mojolicious/mojo-mcp/workflows/linux/badge.svg)](https://github.com/mojolicious/mojo-mcp/actions) [![](https://github.com/mojolicious/mojo-mcp/workflows/macos/badge.svg)](https://github.com/mojolicious/mojo-mcp/actions) [![](https://github.com/mojolicious/mojo-mcp/workflows/windows/badge.svg)](https://github.com/mojolicious/mojo-mcp/actions)

  [Model Context Protocol](https://modelcontextprotocol.io/) support for [Perl](https://perl.org) and the
  [Mojolicious](https://mojolicious.org) real-time web framework.

### Features

Please be aware that this module is still in development and will be changing rapidly. Additionally the MCP
specification is getting regular updates which we will implement. Breaking changes are very likely. The protocol
revision currently implemented is `2026-07-28`.

  * Tool calling, prompts and resources
  * Streamable HTTP and Stdio transports
  * Stateless protocol, with no handshake and no session to keep alive
  * Routing header validation, so gateways and servers can never disagree about what was called
  * JSON Schema 2020-12 validation of tool arguments
  * Progress and log notifications on the response stream of the request they belong to
  * Cancellation as a first-class signal, so long-running tools can stop early
  * Multi-round tool requests with integrity-protected request state
  * Cache hints for discovery, list and read results
  * Notifications for list changes (tools, prompts, resources)
  * OAuth scopes for tools, prompts and resources
  * Scalable with pre-forking web server and async tools using promises
  * HTTP client for testing
  * Can be embedded in Mojolicious web apps

Not supported yet: pagination, resource templates, completion, tasks, MCP Apps, and resource subscriptions. The
roots, sampling and logging client features are deprecated in this revision and are not implemented. New OAuth
clients should use client ID metadata documents, since dynamic client registration is deprecated as well.

## Installation

  All you need is Perl 5.20 or newer. Just install from [CPAN](https://metacpan.org/pod/MCP).

    $ cpanm -n MCP

  We recommend the use of a [Perlbrew](http://perlbrew.pl) environment.

  Then follow the [tutorial](https://metacpan.org/pod/MCP#TUTORIAL), which builds a real server one feature at a
  time.

## Streamable HTTP Transport

Use the `to_action` method to add an MCP endpoint to any Mojolicious application.

```perl
use Mojolicious::Lite -signatures;

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

any '/mcp' => $server->to_action;

app->start;
```

Authentication can be added by the web application, just like for any other route. OAuth scopes can be enforced per
tool, prompt and resource.

## Notifications

Notifications that belong to a request, such as progress reports, are delivered on the response stream of that very
request, which is upgraded from a plain JSON response to SSE whenever there is something to deliver. No extra
configuration is required, and it works under a pre-forking web server.

```perl
use Mojolicious::Lite -signatures;

use MCP::Server;

my $server = MCP::Server->new;
$server->tool(
  name         => 'echo',
  description  => 'Echo the input text',
  input_schema => {type => 'object', properties => {msg => {type => 'string'}}, required => ['msg']},
  code         => sub ($tool, $args) {
    $tool->context->notify_progress(1, 2, "Echoing: $args->{msg}");
    return "Echo: $args->{msg}";
  }
);

any '/mcp' => $server->to_action;

app->start;
```

Notifications that do not belong to a request, such as `list_changed`, need a long-lived stream, which clients open
with a `subscriptions/listen` request. That does require per-process state and is not compatible with pre-forking
web servers, so it is opt-in with `streaming`.

```perl
any '/mcp' => $server->to_action({streaming => 1});
```

## Stdio Transport

Build local command line applications and use the stdio transport for testing with the `to_stdio` method.

```perl
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

$server->to_stdio;
```

Just run the script and type requests on the command line. Every request has to declare the protocol version it is
made with and the capabilities of the client making it.

```
$ perl examples/echo_stdio.pl
{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}
{"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"echo","arguments":{"msg":"hello perl"},"_meta":{"io.modelcontextprotocol/protocolVersion":"2026-07-28","io.modelcontextprotocol/clientCapabilities":{}}}}
```
