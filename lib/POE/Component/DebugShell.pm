package POE::Component::DebugShell;
# $Header: /cvsroot/sungo/POE-Component-DebugShell/lib/POE/Component/DebugShell.pm,v 1.14 2004/02/27 00:38:27 sungo Exp $

use warnings;
use strict;

use 5.006;

use Carp;

use POE;
use POE::Wheel::ReadLine;
use POE::API::Peek;


our $VERSION = (qw($Revision: 1.14 $))[1];
our $RUNNING = 0;
our %COMMANDS;
our $SPAWN_TIME;

sub spawn { #{{{
    my $class = shift;

    # Singleton check {{{
    if($RUNNING) {
        carp "A ".__PACKAGE__." session is already running. Will not start a second.";
        return undef;
    } else {
        $RUNNING = 1;
    }
    # }}}

    
    my $api = POE::API::Peek->new() or croak "Unable to create POE::API::Peek object";


    # Session creation {{{
    my $sess = POE::Session->create(
        inline_states => {
            _start      => \&_start,
            _stop       => \&_stop,

            term_input  => \&term_input,
        },
        heap => {
            api         => $api,
        },
    );
    # }}}

    if($sess) {
        $SPAWN_TIME = time();
        return $sess;
    } else {
        return undef;
    }
} #}}}



sub _start { #{{{
    $_[KERNEL]->alias_set(__PACKAGE__." controller");    
    $_[HEAP]->{rl} = POE::Wheel::ReadLine->new( InputEvent => 'term_input' );
    $_[HEAP]->{prompt} = 'debug> ';
    
    $_[HEAP]->{rl}->clear();
    _output("Welcome to POE Debug Shell v$VERSION");
    
    $_[HEAP]->{rl}->get($_[HEAP]->{prompt});

} #}}}



sub _stop { #{{{
    # Shut things down
    $_[HEAP]->{vt} && $_[HEAP]->{vt}->delete_window($_[HEAP]->{main_window});
} #}}}



sub term_input { #{{{
    my ($input, $exception) = @_[ARG0, ARG1];

    unless (defined $input) {
        croak("Received exception from UI: $exception");
    }

    $_[HEAP]->{rl}->addhistory($input);

    if($input =~ /^help (.*?)$/) {
        my $cmd = $1;
        if($COMMANDS{$cmd}) {
            if($COMMANDS{$cmd}{help}) {
                _output("Help for $cmd:");
                _output($COMMANDS{$cmd}{help});
            } else {
                _output("Error: '$cmd' has no help.");
            }
        } else {
            _output("Error: '$cmd' is not a known command");
        }
    } elsif ( ($input eq 'help') or ($input eq '?') ) {
        my $text;
        _output(' ');
        _output("General help for POE::Component::DebugShell v$VERSION");
        _output("The following commands are available:");
        foreach my $cmd (sort keys %COMMANDS) {
            no warnings;
            my $short_help = $COMMANDS{$cmd}{short_help} || '[ No short help provided ]';
            _output("\t* $cmd - $short_help"); 
        }
        _output(' ');
        
    } else  {
        my ($cmd, @args);
        if($input =~ /^(.+?)\s+(.*)$/) {
            $cmd = $1;
            my $args = $2;
            @args = split('\s+',$args) if $args;
        } else {
            $cmd = $input;
        }

        if($COMMANDS{$cmd}) {
            eval { $COMMANDS{$cmd}{cmd}->( api => $_[HEAP]->{api}, args => \@args); };
            if($@) {
                _output("Error running $cmd: $@");
            }
        } else {
            _output("Error: '$cmd' is not a known command");
        }
    }

    $_[HEAP]->{rl}->get($_[HEAP]->{prompt});
       
} #}}}



sub _output { #{{{
    my $msg = shift || ' ';
    my $heap = $poe_kernel->get_active_session->get_heap;
    $heap->{rl}->put($msg);
} #}}}


#   ____                                          _     
#  / ___|___  _ __ ___  _ __ ___   __ _ _ __   __| |___ 
# | |   / _ \| '_ ` _ \| '_ ` _ \ / _` | '_ \ / _` / __|
# | |__| (_) | | | | | | | | | | | (_| | | | | (_| \__ \
#  \____\___/|_| |_| |_|_| |_| |_|\__,_|_| |_|\__,_|___/
#                                                       
# {{{

%COMMANDS = ( #{{{

    'exit' => {
        help => "Exit the shell",
        short_help => 'Exit the shell',
        cmd => \&cmd_exit,      
    },

    'reload' => {
        help => "Reload the shell to catch updates.",
        short_help => "Reload the shell to catch updates.",
        cmd => \&cmd_reload,
    },
    
    show_sessions => {
        help => 'Show a list of all sessions in the system. The output format is in the form of loggable session ids.',
        short_help => 'Show a list of all sessions',
        cmd => \&cmd_show_sessions,
    },

    'list_aliases' => {
        help => 'List aliases for a given session id. Provide one session id as a parameter.',
        short_help => 'List aliases for a given session id.',
        cmd => \&cmd_list_aliases,
    },

    'session_stats' => {
        help => 'Display various statistics for a given session id. Provide one session id as a parameter.',
        short_help => 'Display various statistics for a given session id.',
        cmd => \&cmd_session_stats,
    },

    'queue_dump' => {
        help => 'Dump the contents of the event queue.',
        short_help => 'Dump the contents of the event queue.',
        cmd => \&cmd_queue_dump,
    },

    'status' => {
        help => 'General shell status.',
        short_help => 'General shell status.',
        cmd => \&cmd_status,
    },
); #}}}

###############

sub cmd_exit { #{{{
    _output('Exiting...');
    exit;
} #}}}

sub cmd_reload { #{{{
    {
        _output("Reloading....");
        eval q|
            no warnings qw(redefine);
            $SIG{__WARN__} = sub { };
            
            foreach my $key (keys %INC) {
                if($key =~ m#POE/Component/DebugShell#) {
                    delete $INC{$key};
                } elsif ($key =~ m#POE/API/Peek#) {
                    delete $INC{$key};
                }
            }
            require POE::Component::DebugShell;
        |;
        _output("Error: $@") if $@;
    }
} #}}}

sub cmd_show_sessions { #{{{
    my %args = @_;
    my $api = $args{api};
     
    _output("Session List:");
    my @sessions = $api->session_list;
    foreach my $sess (@sessions) {
        
        my $id = $sess->ID. " [ ".$api->session_id_loggable($sess)." ]";
        _output("\t* $id");
    }
} #}}}

sub cmd_list_aliases { #{{{
    my %args = @_;
    my $user_args = $args{args};
    my $api = $args{api};
    
    if(my $id = shift @$user_args) {
        if(my $sess = $api->resolve_session_to_ref($id)) {
            my @aliases = $api->session_alias_list($sess);
            if(@aliases) {
                _output("Alias list for session $id");
                foreach my $alias (sort @aliases) {
                    _output("\t* $alias");
                }
            } else {
                _output("No aliases found for session $id");
            }
        } else {
            _output("** Error: ID $id does not resolve to a session. Sorry.");
        }

    } else {
        _output("** Error: Please provide a session id");
    }
}

# }}}

sub cmd_session_stats { #{{{
    my %args = @_;
    my $user_args = $args{args};
    my $api = $args{api};
    if(my $id = shift @$user_args) {
        if(my $sess = $api->resolve_session_to_ref($id)) {
            my $to = $api->event_count_to($sess);
            my $from = $api->event_count_from($sess);
            _output("Statistics for Session $id");
            _output("\tEvents coming from: $from");
            _output("\tEvents going to: $to");
            
        } else {
            _output("** Error: ID $id does not resolve to a session. Sorry.");
        }


    } else {
        _output("** Error: Please provide a session id");
    }
    

} #}}}

sub cmd_queue_dump { #{{{
    my %args = @_;
    my $api = $args{api};
    my $verbose;
    if(defined $args{args} && (@{$args{args}}[0] eq '-v')) {
        $verbose = 1;
    }
    
    my @queue = $api->event_queue_dump();
    
    _output("Event Queue:");
  
    foreach my $item (@queue) {
        _output("\t* ID: ". $item->{ID}." - Index: ".$item->{index});
        _output("\t\tPriority: ".$item->{priority});
        _output("\t\tEvent: ".$item->{event});

        if($verbose) {
            _output("\t\tSource: ".
                    $api->session_id_loggable($item->{source})
                   );
            _output("\t\tDestination: ".
                    $api->session_id_loggable($item->{destination})
                   );
            _output("\t\tType: ".$item->{type});

            _output();
        }
    }

} #}}}

sub cmd_status { #{{{
    my %args = @_;
    my $api = $args{api};
    my $sess_count = $api->session_count;
    _output();
    _output("This is ".__PACKAGE__." v".$VERSION);
    _output("running inside $0.");
    _output("This console was spawned at ".localtime($SPAWN_TIME).'.');
    _output("There are $sess_count known sessions (including the kernel),");
    _output();
} # }}}

# }}}

1;
__END__

=pod

=head1 NAME

POE::Component::DebugShell - Component to allow interactive peeking into a 
running POE application

=head1 SYNOPSIS

    use POE::Component::DebugShell;

    POE::Component::DebugShell->spawn();

=head1 DESCRIPTION

This component allows for interactive peeking into a running POE application.


=cut

=head1 AUTHOR

Matt Cashner (cpan@eekeek.org)

=head1 DATE

$Date: 2004/02/27 00:38:27 $

=head1 LICENSE

Copyright (c) 2003-2004, Matt Cashner

Permission is hereby granted, free of charge, to any person obtaining 
a copy of this software and associated documentation files (the 
"Software"), to deal in the Software without restriction, including 
without limitation the rights to use, copy, modify, merge, publish, 
distribute, sublicense, and/or sell copies of the Software, and to 
permit persons to whom the Software is furnished to do so, subject 
to the following conditions:

The above copyright notice and this permission notice shall be included 
in all copies or substantial portions of the Software.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO
EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut


