#!/usr/bin/env perl

use Modern::Perl;

use BZ::Client::REST;
use Carp::Always;
use Data::Dumper;
use Getopt::Long::Descriptive;
use LWP::UserAgent;
use RT::Client::REST;
use Term::ANSIColor;
use Try::Tiny;
use JSON qw(to_json);
use YAML qw(DumpFile);

my ( $opt, $usage ) = describe_options(
    'tracker-updater.pl',
    [ "rt-url=s", "BWS RT URL", { required => 1, default => $ENV{RT_URL} } ],
    [
        "rt-username=s",
        "BWS RT username",
        { required => 1, default => $ENV{RT_USER} }
    ],
    [
        "rt-password=s",
        "BWS RT password",
        { required => 1, default => $ENV{RT_PW} }
    ],
    [],
    [
        "community-url=s",
        "Community tracker URL",
        { required => 1, default => $ENV{KOHA_URL} }
    ],
    [
        "community-username=s",
        "Community tracker username",
        { required => 1, default => $ENV{KOHA_USER} }
    ],
    [
        "community-password=s",
        "Community tracker password",
        { required => 1, default => $ENV{KOHA_PW} }
    ],
    [],
    [
        'slack|s=s',
        "Slack webhook URL",
        { required => 1, default => $ENV{SLACK_URL} }
    ],
    [],
    [
        'quay-username=s',
        "Quay.io username",
        { required => 1, default => $ENV{QUAY_USERNAME} }
    ],
    [
        'quay-password=s',
        "Slack webhook URL",
        { required => 1, default => $ENV{QUAY_PASSWORD} }
    ],
    [],
    [ 'verbose|v+', "Print extra stuff" ],
    [ 'help|h', "Print usage message and exit", { shortcircuit => 1 } ],
);

print( $usage->text ), exit if $opt->help;

my $verbose = $opt->verbose || 0;

say colored( 'Started: ' . localtime(), 'green' ) if $verbose;

my $rt_url  = $opt->rt_url;
my $rt_user = $opt->rt_username;
my $rt_pass = $opt->rt_password;

my $bz_koha_url  = $opt->community_url;
my $bz_koha_user = $opt->community_username;
my $bz_koha_pass = $opt->community_password;

my $koha_client = BZ::Client::REST->new(
    {
        user     => $bz_koha_user,
        password => $bz_koha_pass,
        url      => $bz_koha_url,
    }
);

my $rt = RT::Client::REST->new(
    server  => $rt_url,
    timeout => 30,
);
try {
    $rt->login( username => $rt_user, password => $rt_pass );
}
catch {
    die "Problem logging in: ", shift->message;
};

my $ua = LWP::UserAgent->new;
$ua->post(
    $opt->slack,
    Content_Type => 'application/json',
    Content => to_json( { text => "Dev Roadmap Dashboard Builder started!" } ),
) if $opt->slack;

qx{ rm hugo-site/content/posts/*.md };

my @queues = ( 'Development' );
foreach my $q (@queues) {
    my $ping_slack = $q eq 'Development';

    # Create tracks
    say colored( "Finding '$q' tickets", 'green' ) if $verbose;

    my $rt_query = qq{ Status = '__Active__' AND Queue = '$q' AND CF.{Published on Roadmap?} = 'Yes' };
    my @ids      = $rt->search(
        type    => 'ticket',
        query   => $rt_query,
        orderby => '-id',
    );

    my @tickets;

    foreach my $ticket_id (@ids) {
        sleep(1);    # pause between requests so we don't kill RT
        my $ticket = $rt->show( type => 'ticket', id => $ticket_id );

        say "TICKET: " . Data::Dumper::Dumper( $ticket ) if $verbose > 2;

        say "Working on ticket " . colored( $ticket_id, 'cyan' )
          if $verbose > 1;
        my ( $bug_id, $others ) = split( ',', $ticket->{'CF.{Community Bug}'} );

        my $published = $ticket->{'CF.{Published on Roadmap?}'} || 'No';
        say "PUBLISHED? : $published" if $verbose > 1;

        next unless $bug_id;
        next unless $published eq 'Yes';

        $bug_id ||= q{};
        $others ||= q{};

        $bug_id =~ s/^\s+|\s+$//g;
        $others =~ s/^\s+|\s+$//g;

        my $yaml;
        $yaml->{subject}        = $ticket->{Subject}                || q{};
        $yaml->{bug_id}         = $bug_id                           || q{};
        $yaml->{work_tbd}       = $ticket->{'CF.{Work to be done}'} || q{};
        $yaml->{koha_module}    = $ticket->{'CF.{Koha Module}'}     || q{};
        $yaml->{koha_component} = $ticket->{'CF.{Koha Component}'}  || q{};
        $yaml->{bug_workflow}   = $ticket->{'CF.{Bug Workflow}'}    || q{};
        $yaml->{koha_version}   = $ticket->{'CF.{Koha Version}'}    || q{};

        my $section = lc($yaml->{koha_module});
        $section =~ s/ /-/g;

        qx{ mkdir -p hugo-site/content/posts/$section };
        DumpFile("hugo-site/content/posts/$section/$bug_id.md", $yaml );
        qx{ echo '---' >> hugo-site/content/posts/$section/$bug_id.md };
    }
}

my $quay_username = $opt->quay_username;
my $quay_password = $opt->quay_password;

# Build the static site
qx{ cd hugo-site && hugo -D && cd .. };
qx{ docker build -t bws-dev-roadmap . };
qx{ docker build -t quay.io/bywatersolutions/koha-dev-roadmap:latest . };
qx{ docker login quay.io --username $quay_username --password $quay_password };
qx{ docker push quay.io/bywatersolutions/koha-dev-roadmap:latest };

$ua->post(
    $opt->slack,
    Content_Type => 'application/json',
    Content => to_json( { text => "Dev Roadmap Dashboard Builder has finished running!" } ),
) if $opt->slack;

say colored( 'Finished: ' . localtime(), 'green' ) if $verbose;

