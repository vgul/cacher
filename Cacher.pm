package Cacher;

#BEGIN { require 5.005; }
BEGIN { require 5.16.0; }

require Exporter;
@ISA = qw(Exporter);

@EXPORT = qw/test get_options run_cmd human_seconds colorize align_right
color_gradient trim sec_to_dhms array_to_hash aws_date_normalize
human_size sec2date sec2date_with_min instance_name_shortener predefined_colors app_name_shortener instance_type_shortener instance_id_shortener ami_shortener
normalize_job_status
color_job_status
info_cache_data
normalize_date
user_color
normalize_gcp_instance_status
normalize_user_name
is_match_lib
normalize_jira_status
color_jira_status
normalize_issuetupe
pr
normalize_date
colored_length
/;


@EXPORT_OK = qw(); #delete_package geniosym);

$VERSION = '1.0';
use v5.16;
use File::Basename;
use File::Path qw(make_path);
use Getopt::Long qw/:config no_ignore_case/;
#use JSON -support_by_pp;
use JSON::XS;
use Data::Dumper;
use YAML::Syck;
use Logfile::Rotate;
use List::Util qw( min max ); 
use Term::ANSIColor ; #qw/:constants/;
use Math::Utils qw/sign/;

use strict;

our %cli_parameters = {};
$cli_parameters{cache_age} = 30*60;

#$cli_parameters{no_wait} = 1;
#$cli_parameters{wait} = 0;


my $lock_file;
$SIG{INT}=\&remove_lock;

sub remove_lock {
    print "\n caught $SIG{INT}",@_,"\n";
    if( $lock_file and -e $lock_file ) {
        my $r = $lock_file;
        $r =~ s/[^\/]//g;
        say STDERR "Lock file '$lock_file' [$r] detected.";
        my $rn = length $r;
        if( $rn < 3 ) {
            say STDERR "Too strange LOCK file name: '$lock_file' [ $rn  <= 3 Condition]";
            say STDERR 'Exiting';
            exit 1;
        } else {
            say STDERR 'Deleting.';
            unlink $lock_file or die  "$!: Can not delete '$lock_file'";
        }

    }
    exit 1;
}

my $cache_dir;
my $cache_root;

my $script_name;
my $cache_dir_default;
BEGIN {

    $cache_root='/var/cache/Cacher';

    if (-e $cache_root and -d $cache_root) {
        #print "SPOON :)\n";
    } else {
        $cache_root='/tmp/Cacher';
        #print "spork :(\n";
    }

    $script_name = readlink $0;
    if( $script_name ) {
        $script_name = basename $script_name;
    } else {
        $script_name = basename $0;
    }

    #$cache_dir = "/tmp/".($script_name).'.Cache';
    $cache_dir_default = "${cache_root}/".($script_name).'.Cache';
    #say "CACHE DIR:", $cache_dir;
    #mkdir $cache_dir unless -d $cache_dir;
    #make_path $cache_dir unless -d $cache_dir;

}

my %get_options_args;
sub get_options {

    my @args_data = @_;

    $get_options_args{'U|use-cache'}             = \$cli_parameters{use_cache};
    $get_options_args{'R|rebuild-cache'}         = \$cli_parameters{rebuild_cache};
    $get_options_args{'A|Auto-use-cache'}        = \$cli_parameters{auto_use_cache};
    $get_options_args{'no-create-cache'}         = \$cli_parameters{no_create_cache};
    $get_options_args{'cache-age=i'}             = \$cli_parameters{cache_age};
    $get_options_args{'I|cache-info'}            = \$cli_parameters{cache_info};
    $get_options_args{'V|Verbose'}               = \$cli_parameters{verbose};
    $get_options_args{'rotate-report'}           = \$cli_parameters{rotate_report};
    $get_options_args{'dry-run'}                 = \$cli_parameters{dry_run};
    $get_options_args{'no-dry-run'}              = \$cli_parameters{no_dry_run};
    $get_options_args{'Vv|VV|extended-verbose'}     = \$cli_parameters{extended_verbose};

    $get_options_args{'NW|no-wait'}              = \$cli_parameters{no_wait};
    $get_options_args{'W|wait'}                  = \$cli_parameters{wait};

    $get_options_args{'help'}                    = \$cli_parameters{help};

    for my $a ( @args_data ) {
        my $var_name = (split /=/, $a)[0];
        $var_name =~ s/-/_/g;
        $var_name =~ s/^(\d)/_\1/;
        #say "VAR NAME [$a]: $var_name";
        $get_options_args{$a} = \${$main::{$var_name}};
        die "Err:". $@ if $@;
    }

    GetOptions( %get_options_args ) or die "Error in command line arguments. Use --help\n";



    if( $cli_parameters{dry_run} and $cli_parameters{no_dry_run} ) {
        say STDERR "Incompatible 'dry-run' and 'no-dry-run' options. Exiting.";
        exit 1;
    }

    #if( $cli_parameters{no_cache} and $cli_parameters{cache} ) {
    #    say STDERR "Incompatible 'cache' and 'no-cache' options. Exiting.";
    #    exit 1;
    #}
    if( $cli_parameters{no_wait} and $cli_parameters{wait} ) {
        say STDERR "Incompatible 'wait' and 'no-wait' options. Exiting.";
        exit 1;
    }


    if( not $cli_parameters{wait} and not $cli_parameters{no_wait} ) {
        $cli_parameters{wait} =1
    }

    if( $cli_parameters{wait} ) {
        $cli_parameters{no_wait} = 0;
    } else {
        $cli_parameters{no_wait} = 1;
    }

    my $tmp_sum;
    for my $k ( qw/ use_cache rebuild_cache auto_use_cache / ) {
        $tmp_sum += $cli_parameters{$k};
    }


    # set default mode
    #$cli_parameters{cache} = 1 unless $cli_parameters{cache} or $cli_parameters{no_cache};

    if( $tmp_sum >= 2 ) {
        say STDERR "Only one of --use-cache, --rebuild-cache, --auto-use-cache options are allowed. Or nothing (--auto-use-cache is default). Exiting.";
        exit 1;
    } elsif( $tmp_sum == 0 ) {
        $cli_parameters{auto_use_cache} = 1;
    }


    if( $cli_parameters{use_cache}
        and (
                    $cli_parameters{no_wait} 
                or  $cli_parameters{wait}
            )
        ) {
        say STDERR 'Using \'--use-cache\' and ( \'wait\' or \'no-wait\' ) has not sense. Probably only \'--use-cache\' ?' if
                 $cli_parameters{verbose} or $cli_parameters{extended_verbose};
    }



    ## auto_use_cache
    if( $cli_parameters{auto_use_cache} and $cli_parameters{no_wait}  ) {
        say STDERR '\'--auto_use_cache and\' \'--no-wait\'' if
                 $cli_parameters{verbose} or $cli_parameters{extended_verbose};
    }

    ## rebuild_cache
    if( $cli_parameters{rebuild_cache} and $cli_parameters{wait} ) {
        say STDERR '\'--rebuild_cache\' and \'--wait\'. Expected' if
                 $cli_parameters{verbose} or $cli_parameters{extended_verbose};
    }

    if( $cli_parameters{rebuild_cache} and $cli_parameters{no_wait} ) {
        say STDERR 'rebuild_cache and no_wait. Expected' if
                 $cli_parameters{verbose} or $cli_parameters{extended_verbose};

    }


    if( $cli_parameters{verbose} or $cli_parameters{extended_verbose} ) {

        say STDERR 'rebuild-cache:  ',  $cli_parameters{rebuild_cache};
        say STDERR 'use-cache:      ',  $cli_parameters{use_cache};
        say STDERR 'auto-use-cache: ',  $cli_parameters{auto_use_cache};
        say STDERR 'wait:           ',  $cli_parameters{wait};
        say STDERR 'no-wait:        ',  $cli_parameters{no_wait};

    }
    #exit 0;
}


#sub get_cache_dir {
#    return $cache_dir_default;
#}

sub run_cmd {
    my %data  = @_;

    #${$data{stderr_collector}} = 134;

    # Parameters:
    #   stderr_collector

    #say Dumper \%data;
    #exit 0;
    die "No CMD specified. Exiting." unless exists $data{cmd};

    #my $cache_age_default = 5*60; # secs
    my $rotate = $data{rotate} || 10;

    my $verbose      = $cli_parameters{verbose} || $data{verbose} || undef;

    my $dry_run      = $cli_parameters{dry_run} || $data{dry_run};;
    my $cache_age    = $data{cache_age} || $cli_parameters{cache_age} || 5*60;
    my $extended_verbose = $cli_parameters{extended_verbose} || $data{extended_verbose};

    my $wait         = $cli_parameters{wait};    # || undef;
    my $no_wait      = $cli_parameters{no_wait}; # || undef;

    my $use_cache           =  $cli_parameters{use_cache};
    my $rebuild_cache       =  $cli_parameters{rebuild_cache}
                     ;#   || $data{rebuild_cache};

                     #say '******* ', $rebuild_cache;

    my $auto_use_cache      =  $cli_parameters{auto_use_cache};

    my $no_create_cache     =  $cli_parameters{no_create_cache};

    my $cache_file;

    undef $cache_dir if $cache_dir;

    my $hard_name = $data{hard_name};

    if( $hard_name ) {


        $cache_file = "${cache_root}/$hard_name";
        $cache_dir = "${cache_root}/$hard_name";


    } else {
        $cache_dir = ${cache_dir_default};
    }

    make_path $cache_dir unless -d $cache_dir;

    my $cache_filename;

    if( $hard_name  and not exists $data{cache_name}) {

#say STDERR 'case1';
        $cache_filename = 'run';

    } else {
        if ( 1 && exists $data{cache_name} ) {
#say STDERR 'case2';
          $cache_filename = $data{cache_name};
          $cache_filename =~ s/\//_/g;
          $cache_filename =~ s/\&/_/g;
          $cache_filename =~ s/\$/_/g;

        } else {
#say STEDER 'case4';

          $cache_filename = $data{cmd};
          $cache_filename =~ s/\s/_/g;
          $cache_filename =~ s/\}/_/g;
          $cache_filename =~ s/\{/_/g;
          $cache_filename =~ s/\[/_/g;
          $cache_filename =~ s/\]/_/g;
          $cache_filename =~ s/\//_/g;
          $cache_filename =~ s/"/_/g;
          $cache_filename =~ s/'/_/g;
          $cache_filename =~ s/\&/_/g;
          $cache_filename =~ s/\\/_/g;

        }
    }
    $cache_file = "$cache_dir/$cache_filename";
    say "FILENAME=$cache_file" if $data{print_filename}; #gag



    $lock_file  = ${cache_file}.".LOCK";



    my $is_cache_exists   = -e $cache_file;

    if( -e $lock_file ) {
        my $lock_info = `ls -l $lock_file`;
        chop $lock_info;
        say STDERR "lock file found '$lock_info`. Exiting";

        if(         $use_cache and     $is_cache_exists ) {
            say 'But --use-cache option specified and cache_file exists too. Run.';
            ## to do: the 'fresh' characteristic print

        } elsif(    $use_cache and not $is_cache_exists ) {
            say STDERR '\'--use-cache\' option specified and cache_file NOT EXISTS.';
            if( $wait ) {

                say STDERR '\'--wait\' option specifed. I will wait';
                wait_lock( $lock_file )

            } else {
                say STDERR '\'--no-wait\' option specifed. Exiting.';
                exit 1;
            }

        } elsif( $rebuild_cache ) {
            say STDERR '\'--rebuild-cache\' option specified';
            if( $wait ) {
                say STDERR '\'--wait\' option specifed. I will wait';
                wait_lock( $lock_file );
            } else {
                say STDERR '\'--no-wait\' option specifed. Exiting.';
                exit 1;
            }
        } elsif( $auto_use_cache ) {
            if( $wait ) {
                say STDERR '\'--wait\' option specifed. I will wait';
                wait_lock( $lock_file );
            } else {
                say STDERR '\'--no-wait\' option specifed. Exiting.';
                exit 1;
            }
        }

        ##unless( $wait ) {
        #    my $lock_info = `ls -l $lock_file`;
        #    chop $lock_info;
        #    say STDERR "lock file found '$lock_info`. Exiting";
        #    say STDERR "Cache directory:";
        #    say STDERR `ls -lt $cache_dir | head`;
        #    #say STDERR "Cache file: $cache_file";
        #    exit 1;
        #    #$lock_file
        #} else {
        #    unless( $cache ) {
        #        say STDERR "Be careful. no-wait option is on. LOCK exists.";
        #        $cache = 1;
        ##    } else {
        #        say STDERR "already locked";
        #        exit 1;
        #    }
        #
        #}
    }


    my $print_cache_info;
    $print_cache_info =1 if $cli_parameters{cache_info}  or $extended_verbose;


    my $is_cache_still_fresh;
    my $cache_mtime;

    if( $is_cache_exists ) {

        my $cache_age_diff;
        my $cache_age_threashold = $cache_age; # ?  $cache_age : $cache_age_default );
        
        $cache_mtime = ((stat ($cache_file))[9]);
        $cache_age_diff = time - $cache_mtime;        

        #$main::_cache_mtime          = $cache_mtime;
        #$main::_cache_age_threashold = $cache_age_threashold;
        #$main::

        if( $cache_age_diff < $cache_age_threashold ) {
            $is_cache_still_fresh = 1;
        }

        #my $message= "Cache: '${cache_file}': Age: ". 
        #            human_seconds( $cache_age_diff, {} ). '  ';

        my $message= "Cache: '${cache_file}': Threashold: ". 
                    human_seconds( $cache_age_threashold ).
                    ". Age: ".  human_seconds( $cache_age_diff, {} ). '. ';



        if( $cache_age_threashold > $cache_age_diff ) {
            $message .= "*** Left: ". 
                    human_seconds( $cache_age_threashold - $cache_age_diff  );

        } elsif( $cache_age_threashold < $cache_age_diff ) {
            $message .= " Forward: ".
                    human_seconds( $cache_age_diff - $cache_age_threashold );
        }

        if( exists $data{cache_info} ) {
          push @{ ${$data{cache_info}} }, 
              $cache_age_diff,
              $cache_age_threashold - $cache_age_diff,
              $cache_age_threashold;
        }
        #$message .= ' = '. human_seconds( $cache_age_threashold );

        say STDERR $message if $extended_verbose or $print_cache_info;

    } else {
        if( $extended_verbose ) {

            say "to REFACTORE: EXTENDED VERBOSE. no_create_cache: $no_create_cache";
            #if( $cache ) {
            #    my $message = "Cache not found. ";
            #    if ( $cli_parameters{no_create_cache} ) {
            #        $message .= "Will not create (reason: '--no-create-cache' option).";
            ##    } else {
            #        $message .= "Will named as '$cache_file'";
            #    }
            #    say STDERR $message;
            #} else {
            #    say STDERR "Cache '$cache_file' not detected.";
            #}
        }
    }


    if( $cli_parameters{rotate_report} ) {
        #say `find $cache_dir/${cache_filename}* -type f \\

        say `find ${cache_file}* -type f \\
        -printf "%TY-%Tm-%Td %TX %10s %u.%g %M %p\n" \\
         |  perl -ne 's/^(\\d{4}-\\d{2}-\\d{2}\\s\\d{2}:\\d{2}:\\d{2})(\\.\\d+)(.*)/\$1\$3/; print ' | sort -r`;

    }

    my ($temp_cache_file, $do_rotate);
    my $cmd;
    my $cmd_output;
    my $run_from_scratch = 1;


    my $stderr_collector_file; 
            $stderr_collector_file =  "$cache_file.STDERR";

    #say Dumper \%data;
    #exit 0;
    if( (     $use_cache and 
            $is_cache_exists # and 
      # not $data{no_cache}  # and
          # $is_cache_still_fresh 
          #

        ) 
        or
        (    $auto_use_cache and
             $is_cache_exists and
             $is_cache_still_fresh
        )
    ) {


#say 'i will use cache';
#exit 0;
        $cmd = "cat $cache_file";

        say STDERR "Running '$cmd' ...". ( $dry_run ? " Dry-run. Exiting" : '' ) if
                $extended_verbose;
        return if $dry_run;

        $cmd_output = `$cmd`;

        #if( -e $stderr_collector_file ) {
        #}
        if( -e $stderr_collector_file and $data{stderr_collector} ) {
            my $stderr = `cat $stderr_collector_file`;
            ${$data{stderr_collector}} = $stderr;
        }


        if( my $validator = $data{consistence_check} ) {

            my $check_cache_consistence = &$validator( $cmd_output );

            if( $check_cache_consistence ) {    
                say STDERR "Consistence check successed" if $extended_verbose;
                undef $run_from_scratch;
            } else {
                say STDERR "Consistence check FAILED. Run from scratch."  if $extended_verbose;
                exit 0;
            }
        } else {
            say STDERR "No check consistence function obtained." if $extended_verbose;
            undef $run_from_scratch;
        }
        return undef unless $run_from_scratch or not $data{quiet_if_cache};
        ## verbose ??
    }
#say 'finish';
#exit 0;
    my $stderr_collector_file; 
            $stderr_collector_file =  "$cache_file.STDERR";
    if( $run_from_scratch ) {
        $cmd = $data{cmd}; 

        if( $data{stderr_collector} ) {

            ## TODO: ROTATE
            `[ -e $stderr_collector_file  ] && rm -v $stderr_collector_file`;
            $cmd .= " 2>$stderr_collector_file ";
        }

        unless ( $cli_parameters{no_create_cache} ) {
            $do_rotate = new Logfile::Rotate( File   => $cache_file, 
                                             Count   => $rotate,
                                             Gzip    => 'no'  ) if $is_cache_exists;
            $temp_cache_file = "$cache_file.TEMP";
            $cmd .= " | tee $temp_cache_file" ;
        }


        say STDERR "Running '$cmd' ...". ( $dry_run ? " Dry-run. Exiting" : '' )
                                 if $verbose or $extended_verbose or $dry_run;
        return if $dry_run;

        my $start = time;

    say STDERR $cmd;
       
        `touch $lock_file`; 
        $cmd_output = `$cmd`;
        ## vlad
    say STDERR 'Output:', $cmd_output;
        `rm $lock_file`;
    #exit(0);

        if( $data{stderr_collector} ) {
            my $stderr = `cat $stderr_collector_file`;
            ${$data{stderr_collector}} = $stderr;
        }

        if( $do_rotate ) {
            $do_rotate->rotate(); 
        }
        rename $temp_cache_file, $cache_file or 
        die "Error renaming: '$temp_cache_file' to '$cache_file': $!" if 
                $temp_cache_file;

        say STDERR "Done. Elapsed: ". (time - $start) . ' second(s)' if $extended_verbose;
    }

    return run_cmd_answer( $cmd_output ) if $data{no_json}; 

    #my $h = from_json( $cmd_output ); 
    my $h = decode_json( $cmd_output ); 

    if( exists $data{skip_key} ) {
        return run_cmd_answer( $h->{$data{skip_key}} );
    }
    return run_cmd_answer( $h );

    sub run_cmd_answer {
        my $data = shift;
        return $data;
    }

}

sub wait_lock {
    my $lf = shift;
    my $wait_cnt=0;

    while( 1 ) {
        return unless -e $lf;
        my $lock_info0 = `ls -l $lf`;
        chop $lock_info0;
        say STDERR "wait: $wait_cnt; $lock_info0";
        $wait_cnt++;
        sleep 1;
    }
}


sub array_to_hash {
    my $array = shift;
    my $key   = shift;

    my %data = ();
    for my $e ( @{ $array } ) {
        unless( exists $e->{$key} ) {
            die "Key $key not exists in element: ". Dumper $e;
        }
        my $k = $e->{$key};

        $data{$k} = $e;
        #last;
    }
    return \%data;

}

sub human_seconds {
    #my $runTime = rand( 10 );
    my $runTime = shift;
    my $params  = shift;

    #say STDERR "Runtime:", $runTime;
    #my $t0;
    #BEGIN { $t0 = time; }
    my $t0 = time;

    #END
    #{
        my $d = $runTime ;#time() - $t0;
        my @int = (
            [ 'second', 1                ],
            [ 'minute', 60               ],
            [ 'hour',   60*60            ],
            [ 'day',    60*60*24         ],
            [ 'week',   60*60*24*7       ],
            [ 'month',  60*60*24*30.5    ],
            [ 'year',   60*60*24*30.5*12 ]
        );
        my $i = $#int;


        my @r;
        while ( ($i>=0) && ($d) )
        {
            if ($d / $int[$i] -> [1] >= 1)
            {
                push @r, sprintf "%d %s%s",
                             $d / $int[$i] -> [1],
                             $int[$i]->[0],
                             ( sprintf "%d", $d / $int[$i] -> [1] ) > 1
                                 ? 's'
                                 : '';
            }
            $d %= $int[$i] -> [1];
            $i--;
        }

        my $runtime = join ", ", @r if @r;
        #warn sprintf "RUNTIME %s\n", $runtime;
        return $runtime;
    #}

    #printf "Runtime is %d\n", $runTime;
    #sleep( $runTime );

}

sub get_options_args {
    return \%get_options_args
}

my %Zcolors = (
    # http://misc.flogisoft.com/bash/tip_colors_and_formatting
        red     =>  31,
        green   =>  32,
        yellow  =>  33,
        blue    =>  34,
        magenta =>  35,
        cyan    =>  36,

        light_grey   => 37,
        dark_grey   =>  90,
        light_blue   => 94,
        NONE         => 4,

        reset        => 0

);

sub colorize {
    local $Term::ANSIColor::AUTORESET = 1;
    my $text = shift;
    my $color = shift;
    my $param  = shift; 

    return $text unless $color and ($color ne 'normal');
    return $text if exists $param->{on} and not $param->{on};
    return colored [$color],  $text;
}

sub color_gradient {
    my $text    = shift;
    my $param   = shift;

    #return $text;
    my $color;
    my @array = @{ $param->{available_gradations} };
    my $n = scalar @array;
    my $i;
    for( $i=0; $i<$n; $i++ ) {
        last if $text eq $array[$i];
    }
       if( $i == 0    )  { $color = 'ON_BRIGHT_GREEN';   }
    elsif( $i == $n-1 )  { $color = 'ON_BRIGHT_RED';     }
    elsif( $i == $n-2 )  { $color = 'ON_BRIGHT_yellow';  }
    else                 { $color = 'ON_BRIGHT_WHITE'; }
    #say "COLOR: $color";
    return colored [ "$color bold" ], $text;
}

sub  trim { my $s = shift; $s =~ s/^\s+|\s+$//g; return $s };

sub sec_to_dhms {
    local $_ = shift;
    $_  = int( $_ );
    my $sign = sign( $_ );

    $_ = abs( $_ ) ;
    my $num  = shift || 1;
    my $type  = shift; #flag space or :


    my ($d, $h, $m, $s);
    my @result; # reverse d h m s
    push @result, $_ % 60; $_ /= 60;
    push @result, $_ % 60; $_ /= 60;
    push @result, $_ % 24; $_ /= 24;
    push @result, $_ % 30; $_ /= 30;
    push @result, $_ % 12; $_ /= 12;
    push @result, int($_);
    #say join ',', reverse @result; 

    my @result2;
    my @letters = qw/ s m h d M y/;
    for ( my $i=5; $i>=0; $i-- ) {
        my $v = $result[$i];
        if( $result[$i] ) {
            push @result2, sprintf '%d%s', $result[$i], $letters[$i];
            last unless --$num;
        }
        #say $i.' ',  $result[$i];
    }

    $sign = ( $sign == -1 ? '-' : '' );

    if( $type eq ' ' )  {

      return $sign. join ' ', @result2; 

    } elsif( $type eq 'smart2' ) {
#say STDERR 'here38';
       my $s = join '',@result2;
       return sprintf "${sign}%d:%02dm", $1, $2 if $s =~ m/^(\d+)h(\d+)m$/;
       return sprintf "${sign}%d:00m",   $1     if $s =~ m/^(\d+)hm$/;
       return sprintf "${sign}%d:%02ds", $1, $2 if $s =~ m/^(\d+)m(\d+)s$/;
       return sprintf "${sign}%d:%00s",  $1     if $s =~ m/^(\d+)m$/;
       return $result2[0];
       
    } else {
      return $sign. join '', @result2; 
    }

}


sub aws_date_normalize {
    my $d = shift;
    if( $d =~ m/(\S+)T/ ) {
        return $1;
    } 
    return $d;
}

sub human_size {
    my $bytes = shift;
    #return `echo ${sum_sizes} | numfmt --to=iec-i`;
    return `echo ${bytes} | numfmt --to=iec | tr -d '\n' `;

}

sub sec2date {
    my $s =shift;
    return `TZ=UTC date -d \@$s +'%F' | tr -d '\n'`;
}

sub sec2date_with_min {
    my $s =shift;
    return `TZ=EEST date -d \@$s +'%F %T' | tr -d '\n'`;
}


sub ami_shortener {
    my $id = shift;
    my $wide = shift;

    if( $wide ) {
      return sprintf "%-21s", $id;
    } else {
      my $a;
      if( length $id == 12 ) {
        $a = $id;
      } else {
        $a = substr( $id, 0, 8 ). '..' . substr( $id, -2 );
      }
      return sprintf "%s", $a;
    }
}

sub instance_id_shortener {
        my $id = shift;
#say 'IN inside: ' . $id;

        $id =~ s/^i-//;
        my $max_for_id = shift;
        my $len0 = length $id;
#say 'manx for id ' . $max_for_id;
#say 'len0 ' . $len0;

        return "i-$id" if $len0 <= $max_for_id;
#say 'Heree ?';
        my $first = substr( $id,0,3 );
        my $middle = ( $len0 == 17 ? '..' :
                               ( $len0 == 7 ? '...' : '..err..' ) );
        my $end   = substr( $id,-2);
        my $first_attempt = $first.$middle.$end ;

        my $len1 = length $first_attempt;
        
        #return $first.$middle.$end unless $max_for_id;
        unless( $max_for_id ) {
            #say $first.$middle.$end ;
            #say 'RETURN NERE';
            return 'I-'. $first_attempt;
        }
        
        my $i_can_add = $max_for_id - $len1;
        
        my $half = int ($i_can_add /2  ) +1;
        my $rest = $i_can_add - $half;

        return
             #'I-'.substr($id,0,3+$half).
             substr($id,0,3+$half).
            $middle.
            substr($id,-2-$rest); #. '     '.$add; #. '+'. $add;
}

sub instance_name_shortener {
    my $in = shift;
    my $width  = shift; # || 60;

    my $tmp_name = $in;

    #say 'IN=' . $in;
    my $to_del_id_shortener = sub {
        my $id = shift;
        my $max_for_id = shift;

        my $len0 = length $id;
        return $id if $len0 <= $max_for_id;

        my $first = substr( $id,0,3 );
        my $middle = ( $len0 == 17 ? '..' :
                               ( $len0 == 7 ? '...' : '..err..' ) );
        my $end   = substr( $id,-2);
        my $first_attempt = $first.$middle.$end ;

        my $len1 = length $first_attempt;
        
        #return $first.$middle.$end unless $max_for_id;
        unless( $max_for_id ) {
            #say $first.$middle.$end ;
            return $first_attempt;
        }
        
        my $i_can_add = $max_for_id - $len1;
        
        #say "$len0 : $max_for_id - $len1 = $i_can_add";
        #if( $i_can_add == 0 ) { 
        ##    return $first_attempt;
        #    }
        #say 'length $id:', length $id;
        #say 'length $middle:', length $middle;
        #say 'max_for_id: ', $max_for_id;
        #my $i_can_add = length( $id) - length ($middle);
        #say 'real_width:', $real_width;


        my $half = int ($i_can_add /2  ) +1;
        my $rest = $i_can_add - $half;
        #say "HALF:$half : REST:$rest";

        #say 'half: ', $half;
        #say 'rest ', $rest;

        return
             substr($id,0,3+$half).
            $middle.
            substr($id,-2-$rest); #. '     '.$add; #. '+'. $add;
    };

    if( $in =~ m/(.\S+)-i-([a-z0-9]+)/ and grep length $2 == $_, qw/ 8 17 / ) {
        #say 'me here';
        my $app = $1;
        my $id  = $2;

        #return "$app-$id";
        $app = app_name_shortener( $app );

        
        #my $add;
        #if ( $width ) {
        #    $add = $width - length "${app}-i-";
        #    #printf STDERR "%2d ** %s\n", $add, $app;
        #} 
        #say 'FFF:', $width - length "${app}-i-";

        #$id = &$id_shortener( $id, $width ? $width - length "${app}-i-" : undef );
        #say $id, ' ', $width;
        $id = instance_id_shortener( $id, $width ? $width - length "${app}-i-" : undef );
        #say $id;


        #return ":${add}:${app}-i-${id}";
        #return "$add:${app}-i-${id}";
        #say STDERR "$add  **  $app";

        return "${app}-${id}";
    }

    if( $in =~ m/^va/ ) {
        return "VA:$in";
    }
    return "E:$in";
   

    #return "$l:$tmp_name";
}

sub app_name_shortener {
  my $s = shift;

  $s =~ s/Company-/e.-/;

  $s =~ s/assist-connector/ass.conn./;
  $s =~ s/banner-/ban.-/;
  $s =~ s/registrator/reg./;
  $s =~ s/gateway-db/gateway-db/;
  $s =~ s/gateway-worker/g.way-wrk/;
  $s =~ s/gateway/g.w./;
  #$app =~ s/worker-/wrk.-/;
  $s =~ s/scribe-interpreter/scribe-int./;
  $s =~ s/historyanalyzer-/hist.anlz.-/;
  $s =~ s/planner-pipeline-/plan.pipe.-/;

  return $s;

}


sub predefined_colors {
  my $values = shift;
  my $colors = shift;

  my $min = min @{ $values };
  my $max = max @{ $values };
  my $num = scalar @{ $values };
  my $num_colors = scalar @{ $colors };
  my $delta = int( ( $max - $min ) / $num_colors );

  #say "num; $num_colors : min: $min, max: $max : ".
  #        "diapazon: ", ( $max - $min ). '  '.
  #        'delta: ', $delta; #( $max - $min ) / $num_colors;
  
  my $res;
  my $ccnt = 0;
  for my $v ( sort { $a <=> $b }  @{ $values } ) {

    #printf "CCNT: $ccnt: mul; %4d; $v\n", $ccnt * $delta;
    $res->{$v} = $colors->[$ccnt];

    if( $v > $ccnt * $delta + $min && $ccnt < $num_colors-1 ) {
      $ccnt++;
    }

  }
  return $res;
}


sub instance_type_shortener {
  my $s = shift;
  $s =~ s/^t2\.//;
  $s =~ s/medium/med/;
  $s =~ s/small/sml/;
  $s =~ s/large/lrg/;
  $s =~ s/micro/mcr/;
  $s =~ s/nano/nan/;
  return $s;
}

sub align_right {
  my $start   = shift;
  my $end     = shift;
  my @strings = @_;

  my @out;
  my $len = 0;
  for my $s ( @strings ) {
    my $string = $s->[0];
    $len += length $string;
    if( $s->[1] ) {
      $string = colorize( $string, $s->[1] );
    }
    push @out, $string;
  }
  #return ' 'x($end - $start - $len - scalar @out -2), join '', @out;
  return ' 'x($end - $start - $len ), join '', @out;
}



my %cloudbees_job_statuses = (
   	"completed_abort"   => { abbr => 'Ca', color=>'bold red' },
		"completed_error"   => { abbr => 'Ce', color=>'magenta' },
    "completed_success" => { abbr => 'C+', color=>'bold green' },
    "completed_warning" => { abbr => 'Cw', color=>'bold yellow' },
    "running_error"     => { abbr => 'Re', color=>'yellow' },
    "running_success"   => { abbr => 'R+', color=>'green' } );

sub normalize_job_status {
  my $status = shift;

 	#return colorize( $s{$status}->{abbr}, $s{$status}->{color}) if exists $s{$status};
 	return $cloudbees_job_statuses{$status}->{abbr} if exists $cloudbees_job_statuses{$status};
	return $status;
}

sub normalize_date {
  my $d = shift;
  # 2021-01-26T15:42:25.874Z
  $d =~ s/T/ /;
  #return 14;
  return substr $d, 0, 16;
}


sub color_job_status {
  my $status = shift;

 	#return colorize( $s{$status}->{abbr}, $s{$status}->{color}) if exists $s{$status};
 	return $cloudbees_job_statuses{$status}->{color} if exists $cloudbees_job_statuses{$status};
	return undef;
}


sub user_color {
  my $user = shift;
  my %user_colors = (
    'mdattatreya@cloudbees.com' => 'bold red', 
    'vgula@cloudbees.com'=>'bold yellow',
    'vgula@cl' => 'bold yellod',
    'product-security-jira-defectdojo@cloudbees.com' => 'cyan'
    );

  return $user_colors{$user} if exists $user_colors{$user};
  return 'bold blue';
}

sub normalize_gcp_instance_status {
  my $status = shift;
  return substr $status, 0,  2;
}

sub is_match_lib {
  my $re = shift;
  my @items_to_check = @_;

  #print Dumper @items_to_check;

  my $found = undef;
  for my $t ( @{ $re } ) {
    #say $t;
    #say $_;
    if( 
      grep $_ =~ m/$t/, @items_to_check
      ) {
      $found =1;
      last;
    }
  }
  return $found;
}

sub normalize_user_name {
  my $user = shift;
  $user =~ s/mdattatreya\@cloudbees.com/mohan/;
  $user =~ s/\@cloudbees.com/\@c../;
  $user =~ s/product-security-jira-defectdojo/..defectdojo/;
  return $user;
}

my %jira_statuses = (
  'Open'        => { abbr=> 'Opn', color=>'blue' },
  'Resolved'    => { abbr=> 'Rsv', color=>'green bold' },
  'Closed'      => { abbr=> 'Cls', color=>'green' },
  'In Progress' => { abbr=> 'iPr', color=>'yellow bold' },
  'In Review'   => { abbr=> 'iRv', color=>'cyan bold' },
  'On hold'   => { abbr=> 'Hol', color=>'cyan' },
);

sub normalize_jira_status {
  my $s = shift;

  if( exists $jira_statuses{$s} ) {
   return $jira_statuses{$s}->{abbr};
  }
  return $s;
}

sub color_jira_status {
  my $s = shift;

  if( exists $jira_statuses{$s} ) {
    return $jira_statuses{$s}->{color};
  }
  return undef;
}

my %issuetypes = (
   	"Epic"   => { abbr => 'E', color=>'bold red' },
   	"Task"   => { abbr => 'T', color=>'normal' },
   	"Bug"   => { abbr => 'B', color=>'normal' },
   	"Problem"   => { abbr => 'P', color=>'normal' },
);

sub normalize_issuetupe {
  my $t = shift;
  #print $t, Dumper \%issuetypes;
 	return $issuetypes{$t}->{abbr} if exists $issuetypes{$t};
 	return $t;
  
}

sub pr {
  my $a = shift;
  my $l = shift;
  my @data = @_;
  my @tmp = ();
  for my $d ( @data ) {
    my $string = $d->[0];
    $$l  += length $string;
    #$len += length $string;
    if( $d->[1] ) {
      $string = colorize( $string, $d->[1] );
    }
    push @tmp, $string;
  }
  push @{ $a }, join '',@tmp;

}

sub DEPR_normalize_date {
  my $s = shift;
  $s =~ s/T/ /;
  $s =~ s/Z//;
  return $s;
}

sub colored_length {
  my $str = shift;
  #return length shift;
  #$str =~ s/\33\[(\d+(;\d+)?)?[musfwhojBCDHRJK]//g;# if $self->{options}{allowANSI}; # maybe i should only have allowed ESC[#;#m and not things not related to
  $str =~ s/\33\[(\d+((;\d+);\d+)?)?[musfwhojBCDHRJK]//g;# if $self->{options}{allowANSI}; # maybe i should only have allowed ESC[#;#m and not things not related to
  $str =~ s/\33\([0B]//g; # if $self->{options}{allowANSI};                           # color/bold/underline.. But I want to give people as much room as they need.
  return length $str;

}
1;


__END__

=head1 NAME

Cacher - Perl module to organize work with common enities

=head1 SYNOPSIS

  use Cacher;

  # supplies following functions 

    * get_options_args('mask=s')

    * run_cmd( %HASH )
    
    * Cacher::get_options_args;

    * sec2date( seconds );

=head1 DESCRIPTION

One of purposes of this package is cache output of execution of any shell command

=over 4

=item get_options_args( LIST OF STRINGS )

C<get_options_args> invokes like

    our $mask;
    get_options_args('mask=s')

it pass list of strings to standard C<Getopt::Long> GetOptions() function;
Predefined parameters you can see as

    say Dumper Cacher::get_options_args;

=item run_cmd( %HASH )

    run system command and cache result
    keys/values see in code yet

=back

=head1 DEPENDANCIES

    use GetOptins;
    use JSON -support_by_pp;

=head1 SEE ALSO

L<Data::Dumper>

=head1 AUTHOR

Vladyslav Gula <vladyslav.gula@gmail.com>

=cut
