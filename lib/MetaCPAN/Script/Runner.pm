package MetaCPAN::Script::Runner;

use strict;
use warnings;

use Config::ZOMG ();
use File::Path   ();
use Hash::Merge::Simple qw(merge);
use IO::Interactive qw(is_interactive);
use Module::Pluggable search_path => ['MetaCPAN::Script'];
use Module::Runtime ();
use Try::Tiny qw( catch try );
use Term::ANSIColor qw( colored );

our $EXIT_CODE = 0;

sub run {
    my ( $class, @actions ) = @ARGV;
    my %plugins
        = map { ( my $key = $_ ) =~ s/^MetaCPAN::Script:://; lc($key) => $_ }
        plugins;
    die "Usage: metacpan [command] [args]" unless ($class);
    Module::Runtime::require_module( $plugins{$class} );

    my $config = build_config();

    foreach my $logger ( @{ $config->{logger} || [] } ) {
        my $path = $logger->{filename} or next;
        $path =~ s{([^/]+)$}{};
        -d $path
            or File::Path::mkpath($path);
    }

    my $obj = undef;
    my $ex  = undef;
    try {
        $obj = $plugins{$class}->new_with_options($config);

        $obj->run;
    }
    catch {
        $ex = $_;

        $ex = { 'message' => $ex } unless ( ref $ex );

        unless ( defined $ex->{'message'} ) {
            $ex->{'message'} = $ex->{'msg'}   if ( defined $ex->{'msg'} );
            $ex->{'message'} = $ex->{'error'} if ( defined $ex->{'error'} );
        }

        if ( defined $obj
            && $obj->exit_code != 0 )
        {
            # Copying the Exit Code to propagate it to the superior level
            $EXIT_CODE = $obj->exit_code;
        }
        elsif ( $! != 0 ) {
            $EXIT_CODE = 0 + $!;
        }
        else {
            $EXIT_CODE = 1;
        }

        # Display Exception Message in red
        print colored( ['bold red'],
            "*** EXECPTION [ $EXIT_CODE ] ***: " . $ex->{'message'} ),
            "\n";
    };

    unless ( defined $ex ) {

        # Copying the Exit Code to propagate it to the superior level
        $EXIT_CODE = $obj->exit_code;
    }

    return ( $EXIT_CODE == 0 );
}

sub build_config {
    my $config = Config::ZOMG->new(
        name => 'metacpan',
        path => 'etc'
    )->load;
    if ( $ENV{HARNESS_ACTIVE} ) {
        my $tconf = Config::ZOMG->new(
            name => 'metacpan',
            file => 'etc/metacpan_testing.pl'
        )->load;
        $config = merge $config, $tconf;
    }
    elsif ( is_interactive() ) {
        my $iconf = Config::ZOMG->new(
            name => 'metacpan',
            file => 'etc/metacpan_interactive.pl'
        )->load;
        $config = merge $config, $iconf;
    }
    return $config;
}

# AnyEvent::Run calls the main method
*main = \&run;

1;
