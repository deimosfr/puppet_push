#!/usr/bin/perl 
#===============================================================================
#
#         FILE:  puppet_push
#
#        USAGE:  ./puppet_push  
#
#  DESCRIPTION:  This program push a request to puppet clients for a synchronisation
#
#      OPTIONS:  ---
# REQUIREMENTS:  You need to have a ssh key exchange with all your wished nodes
#                You also need a symlink of puppetd : ln -s /opt/csw/bin/puppetd /usr/bin/
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Pierre Mavro (), pierre@mavro.fr
#      COMPANY:  
#      VERSION:  0.1b
#      CREATED:  04/06/2010 16:23:07
#     REVISION:  ---
#===============================================================================

use strict;
use warnings;
no warnings 'closure';
use Getopt::Long;
use threads;
use threads::shared;
use Term::ANSIColor;
use Sys::Hostname;

# Help print
sub help
{
    print <<"print_help";
Usage : puppet_push [-h] [-l|-s] [-pca puppetca_path] [-n nodes] [-e nodes] [-t tag] [-y] [-mt threads] [-v] [-d]

Options :
-h, --help\n\tPrint this help screen
-l, --list\n\tList registered nodes
-s, --sync\n\tSend a request on Puppet clients for sync
-pca\n\tSet puppetca binary full path (default is /usr/sbin/puppetca)
-n\n\tNodes to be synchronized from master
-e\n\tNodes to exclude from synchronisation
-t\n\tSet tags (Puppet class) to sync (default all)
-y, --yesall\n\tAlways answer yes to any questions
-mt, --simultanous\n\tNumber of maximum simultanous clients sync requests (Default is 2)
-v, --verbose\n\tVerbose output
-d, --debug\n\tDebug mode

Examples :
puppet_push -l
puppet_push -s -n puppet_fr_client-\\d+ -n puppet_us_client-\\d+ -e puppet_client-2.mydomain.com -t ntp -t ldapclient -mt 4
print_help
    exit 1;
}

# Check arguments
sub check_opts
{
    help unless(defined(@ARGV));
    
    # Vars
    my ($puppetca_bin, $list, $nodes_file, $sync, @nodes, @exclude, @tags, $yes, $max_threads, $verbose, $debug);

    # Set options
    GetOptions( "help|h"            => \&help,
                "l|list"            => \$list,
                "pca=s"             => \$puppetca_bin,
                "s|sync"            => \$sync,
                "n=s"               => \@nodes,
                "e=s"               => \@exclude,
                "t=s"               => \@tags,
                "y|yesall"          => \$yes,
                "mt|simultanous=s"  => \$max_threads,
                "v|verbose"         => \$verbose,
                "d|debug"           => \$debug);

    # Check if defined 
    unless (defined($puppetca_bin))
    {
       $puppetca_bin='/usr/sbin/puppetca';
    }
    unless (-x $puppetca_bin)
    {
       print "Sorry but $puppetca_bin is not executable for this user or not found\n";
       exit 1;
    }
    
    # Check number of requested threads
    unless ($max_threads)
    {
        $max_threads=2;
    }
    
    # List mode asked
    if ($list)
    {
        print "\nPlease wait while collecting data...";
        list_registred_nodes($puppetca_bin);
        exit 0;
    }

    # Synchronize nodes
    if ($sync)
    {
        sync($puppetca_bin,\@nodes,\@exclude,\@tags,$yes,$max_threads,$verbose,$debug);
    }
}

# Get registered nodes from puppetca 
sub get_registred_nodes
{
    my $puppetca_bin = shift;
    my $host = hostname;
    my @all_nodes;
    
    # Execute puppetca bin to get all the list of node and check those which can be deployed
    open (PUPPETCA, "$puppetca_bin --list --all |") or die "Can't execute $puppetca_bin : $!\n";
    while (<PUPPETCA>)
    {
        chomp $_;
        if (/^\+\s*(.+)/)
        {
            my $current_node = $1;
            if ($current_node !~ /^$host/)
            {
                push @all_nodes, $1;    
            }
        }
    }
    close (PUPPETCA);
    
    return \@all_nodes;
}

# List all registered nodes
sub list_registred_nodes
{
    my $puppetca_bin = shift;

    # Get all egistred nodes
    my $all_nodes = get_registred_nodes($puppetca_bin);
    my $total_nodes = @$all_nodes;

    # Print them
    print "\rList of available registred nodes ($total_nodes) :\n\n";
    foreach (@$all_nodes)
    {
        print "$_\n"; 
    }
}

# Set OK color in green and FAILED in red
# 1st arg is message line and 2nd is ok or failed
sub print_color
{
    # Print if last arg is 1 it won't replace the current line
    
    # Print message
    printf "%-60s", "$_[0]";

    # Print OK in green
    if ($_[1] =~ /ok|reussi/i)
    {   
        print color 'bold green';
    }   
    elsif ($_[1] =~ /fail/i)
    {   
        # Print failed in red
        print color 'bold red';
    }
    else
    {
        print color 'white';
    }

    # Print result
    printf "%20s", "$_[1]\n";

    # Resetting colors
    print color 'reset';
}

sub sync
{
    my $puppetca_bin=shift;
    my $ref_nodes=shift;
    my @nodes = @$ref_nodes;
    my $ref_exclude = shift;
    my @exclude = @$ref_exclude;
    my $ref_tags = shift;
    my @tags = @$ref_tags,
    my $yes=shift;
    my $max_threads=shift;
    my $tags_list;
    my $verbose = shift;
    my $debug = shift;

    # Get registred_nodes
    my $ref_registred_nodes = get_registred_nodes($puppetca_bin);
    my @registred_nodes = @$ref_registred_nodes;

    # Syncronization function   
    sub launch_sync
    {
        my $total_nodes_to_sync=shift;
        my $ref_nodes_to_sync=shift;
        my @nodes_to_sync : shared = @$ref_nodes_to_sync;
        my $full_tags = shift;
        $full_tags = 1 unless (defined($full_tags));
        my $max_threads=shift;
        my @threads;
        my $analyze=shift;

        # Multitreading tasks
        sub launch_thread
        {
            my $full_tags=shift;
            $full_tags = '' if ($full_tags eq '1');
            my $analyze = shift;
            
            # Launch code to ask puppet clients to synchronize
            sub execute
            {
                my $node = shift;
                my $full_tags = shift;
                my $analyze = shift;

                # Launch puppet client sync with or not debug/verbose mode
                if ($analyze eq '1')
                {
                    system("ssh root\@$node puppetd --no-daemon --onetime $full_tags $analyze");
                }
                else
                {
                    system("ssh root\@$node puppetd --no-daemon --onetime $full_tags 2>&1 > /dev/null");    
                }
                
                # Devide return code to get real exit code;
                return $? / 256;
            }

            # Verify the synchronization between the client and the server
            sub check_result
            {
                my $node = shift;
                my %files;
                my $dir = "/var/lib/puppet/reports/$node";

                # Get latest file
                opendir (REPORTS, $dir) or die "Sorry but I can't open logs file ($dir) : $!\n";
                my @sorted = sort {-M "$dir/$a" <=> -M "$dir/$b"} readdir(REPORTS);
                closedir REPORTS;

                # Verify if there was error or not
                open (YALM, "<$dir/$sorted[0]");
                while (<YALM>)
                {
                    chomp $_;
                    # Detect if there was error or not
                    if (/^\s*level\:/i)
                    {
                        if (/\:err$/)
                        {
                            return 1;
                        }
                    }
                }
                close (YALM);
                return 0;
            }
            
            while (1)
            {
                my $node;
                # Managing shared array in this block
                {
                    lock @nodes_to_sync;
                    $node = shift @nodes_to_sync;
                }
                # Exit when there are no more nodes to sync
                if (!$node)
                {
                    return;
                }
                else
                {
                    my $result=-1;
                    my $return_execute_code = execute($node,$full_tags,$analyze);
                    # Check result
                    if ($return_execute_code == 1)
                    {
                        $result = 1;
                    }
                    else
                    {
                        $result = check_result($node);
                    }
                    if ($result == 0)
                    {
                        print_color("$node","[ OK ]");
                    }
                    elsif ($result == 1)
                    {
                        print_color("$node","[ FAILED ]");
                    }
                    else
                    {
                        print_color("$node","[ UNKNOW ]");
                    }
                }
            }
        }

        # Launching threads
        for (1 .. $max_threads)
        {
            my $thread = threads->create('launch_thread', "$full_tags", "$analyze");
            push @threads, $thread;
        }
        
        # Waiting for threads to finish
        while (@threads)
        {
            my $thread = shift @threads;
            $thread->join ();
        }

        print "\nDone !\n";
    }

    # Detect if tags are asked or multiple. Then sort them in puppet format
    sub check_multi_tags
    {
        my $ref_tags = shift;
        my @tags = @$ref_tags;
        my $total_tags = shift;
        
        if ($total_tags == 1)
        {
            return "--tags $tags[0]";
        }
        elsif ($total_tags > 1)
        {
            my $multi_tags = join ',', @tags;
            return "--tags $multi_tags";
        }
        else
        {
            return;
        }
    }

    # Check tags
    my $total_tags = @tags;
    if ($total_tags > 0)
    {
        $tags_list = "with only @tags tags";
    }
    else
    {
        $tags_list = '';
    }
    my $full_tags = check_multi_tags(\@tags,$total_tags);

    # Verbose and Debug checking
    my $analyze='';
      
    # Check if verbose is asked 
    if ($verbose)
    {
        $analyze .= ' --verbose';
    }
    # Check if debug is asked
    if ($debug)
    {
        $analyze .= ' --debug';
    }

    # Check if requesting a 'all nodes sync'
    unless (@nodes)
    {
        my @needed_array;

        # If auto yes is asked
        unless ($yes)
        {
            # Check if yesall is requested
            print "\nAre you requesting a synchronization for all nodes $tags_list (y/n) ? ";
            my $answer = <STDIN>;
            chomp $answer;

            # Launching synchronization will all nodes
            if ($answer =~ /^y$/i)
            {
                launch_sync('all',\@registred_nodes,$full_tags,$max_threads,$analyze);
            }
            # Exiting because user requested
            elsif ($answer =~ /^n$/i)
            {
                print "Synchronization cancelled by user\n";
                exit 1;
            }
            # unknow answer
            else
            {
                print "Please answer by 'y' or 'n'\n";
                exit 1;
            }
        }
        else
        {
            launch_sync('all',\@registred_nodes,$full_tags,$max_threads,$analyze);
        }
    }
    # Else only sync requested nodes
    else
    {
        my ($registred_node, @nodes_to_sync, $wanted_node, $i);

        # Searching requested nodes
        foreach (@registred_nodes)
        {
            $registred_node = $_;
            $i=2;
            foreach (@nodes)
            {
                # Compare if current node match with requested node to sync
                if ($registred_node =~ /$_/i)
                {
                    if ($i != 0)
                    {
                        $i=1;
                    }
                }
                else
                {
                    $i=0;
                }
            }
            push @nodes_to_sync, $registred_node if ($i == 1);
        }

        # Delete duplicated nodes
        my %saw;
        my @nodes_to_sync_tmp = grep(!$saw{$_}++, @nodes_to_sync);

        # Exclude unwanted nodes
        if (@exclude)
        {
            $i=0;
            foreach (@nodes_to_sync_tmp)
            {
                $wanted_node = $_;
                foreach (@exclude)
                {
                    if ($wanted_node =~ /$_/i)
                    {
                        delete($nodes_to_sync_tmp[$i]);
                    }
                }
                $i++;
            }   
        }

        # Sort and count total nodes
        @nodes_to_sync=();
        foreach (@nodes_to_sync_tmp)
        {
            if ($_)
            {
                push @nodes_to_sync, $_;
            }
        }
        @nodes_to_sync=sort(@nodes_to_sync);
        my $total_nodes_to_sync = @nodes_to_sync;

        # Sync nodes
        if ($total_nodes_to_sync > 0)
        {
            # If auto yes is asked
            unless ($yes)
            {
                # Showing list of node to be sync
                print "\nPuppets clients to be synchronized from the master :\n";
                foreach (@nodes_to_sync)
                {
                    print "$_\n";   
                }

                print "\nAre you sure do you want to continue $tags_list (y/n) ? ";
                my $answer = <STDIN>;
                chomp $answer;
                if ($answer =~ /^y$/i)
                {
                    launch_sync($total_nodes_to_sync,\@nodes_to_sync,$full_tags,$max_threads,$analyze);
                }
                # Exiting because user requested
                elsif ($answer =~ /^n$/i)
                {
                    print "Synchronization cancelled by user\n";
                    exit 1;
                }
                # Unknow answer
                else
                {
                    print "Please answer by 'y' or 'n'\n";
                    exit 1;
                }
            }
            # Else confirm
            else
            {
                print "\nSynchronizing puppets clients with master :\n";
                launch_sync($total_nodes_to_sync,\@nodes_to_sync,$full_tags,$max_threads,$analyze);
            }
        }
        else
        {
            print "Sorry but no nodes match with your requested nodes to sync\n";
            exit 1;
        }
    }
}

check_opts;

