#
# This example is the server built in the MCP tutorial, giving a model access to your local Perl documentation
#
# mcp.json:
# {
#   "mcpServers": {
#     "perldoc": {
#       "command": "/home/kraih/mojo-mcp/examples/perldoc_stdio.pl"
#     }
#   }
# }
#
use Mojo::Base -strict, -signatures;

use Config;
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
$server->prompt(
  name        => 'explain',
  description => 'Explain what a Perl module is for',
  arguments   => [{name => 'module', description => 'Module name', required => 1}],
  code        => sub ($prompt, $args) {
    return "Read the documentation of $args->{module} with the perldoc tool, then explain in three sentences "
      . 'what problem it solves and when to reach for it.';
  }
);
$server->resource(
  uri         => 'file:///perl/config',
  name        => 'perl_config',
  description => 'Configuration of the Perl interpreter running this server',
  mime_type   => 'text/plain',
  cache_ttl   => 3_600_000,
  code        => sub ($resource) {
    return join "\n", map {"$_=$Config{$_}"} qw(archname osname perlpath version);
  }
);

$server->to_stdio;
