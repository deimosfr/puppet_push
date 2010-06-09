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
# REQUIREMENTS:  You need to have a ssh key exchange done with all your wished nodes
#         BUGS:  ---
#        NOTES:  ---
#       AUTHOR:  Pierre Mavro (), pierre@mavro.fr
#      COMPANY:  
#      VERSION:  0.1a
#      CREATED:  04/06/2010 16:23:07
#     REVISION:  ---
#===============================================================================

#use strict;
#use warnings;
use Getopt::Long;
use threads;
use threads::shared;
use Term::ANSIColor;

# Help print
sub help
{
    print <<"print_help";
Usage : puppet_push [-h] [-l|-s] [-pca puppetca_path] [-n nodes] [-y]

Options :
-h, --help\n\tPrint this help screen
-l, --list\n\tList registered nodes
-s, --sync\n\tSend a request for sync
-pca\n\tSet puppetca binary full path
-n\n\tNodes to be synchronized
-e\n\tNodes to exclude from synchronisation
-y, --yesall\n\tAlways answer yes to any questions
-mt, --simultanous\n\tNumber of maximum simultanous clients requests (Default is 2)

Examples :
puppet_push -s
print_help
    exit 1;
}

# Check arguments
sub check_opts
{
    help unless(defined(@ARGV));
    
    # Vars
    my ($puppetca_bin, $list, $nodes_file, $sync, @nodes, @exclude, $yes, $max_threads);

    # Set options
    GetOptions( "help|h"            => \&help,
                "l|list"            => \$list,
                "pca=s"             => \$puppetca_bin,
                "s|sync"            => \$sync,
                "n=s"               => \@nodes,
                "e=s"               => \@exclude,
                "y|yesall"          => \$yes,
                "mt|simultanous=s"  => \$max_threads);

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
        print "\nPlease wait while collecting...";
        &list_registred_nodes($puppetca_bin);
        exit 0;
    }

    # Synchronize nodes
    if ($sync)
    {
        &sync($puppetca_bin,\@nodes,\@exclude,$yes,$max_threads);
    }
}

# Get registered nodes from puppetca 
sub get_registred_nodes
{
    my $puppetca_bin = shift;
    my @all_nodes;
    
    # Execute puppetca bin to get all the list of node and check those which can be deployed
    open (PUPPETCA, "$puppetca_bin --list --all |") or die "Can't execute $puppetca_bin : $!\n";
    while (<PUPPETCA>)
    {
        chomp $_;
        if (/^\+\s*(.+)/)
        {
            push @all_nodes, $1;
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
    my $yes=shift;
    my $max_threads=shift;

    # Get registred_nodes
    my $ref_registred_nodes = get_registred_nodes($puppetca_bin);
    my @registred_nodes = @$ref_registred_nodes;
    #my @registred_nodes;
    #open (FILER, "<liste");
    #while (<FILER>)
    #{
    #chomp $_;
    #    push @registred_nodes, $_;
    #}
    #close (FILER);

    # Syncronization function   
    sub launch_sync
    {
        my $total_nodes_to_sync=shift;
        my $ref_nodes_to_sync=shift;
        my @nodes_to_sync : shared = @$ref_nodes_to_sync;
        my $max_threads=shift;
        my @threads;

        # Multitreading tasks
        sub launch_thread
        {
            # Launch code to ask puppet clients to synchronize
            sub execute
            {
                my $node = shift;

                # Launch puppet client sync
                system("ssh root\@$node puppetd --no-daemon --onetime &> /dev/null");
            }

            # Verify the synchronization between the client and the server
            sub check_result
            {
                my $node = shift;
                my %files;
                my $dir = "/var/lib/puppet/reports/$node";

                # Get latest file
                opendir (REPORTS, $dir) or die "Jen e peux pas ouvrir le dossier de logs : $!\n";
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
                    execute($node);
                    # Check result
                    my $result = check_result($node);
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
            my $thread = threads->create('launch_thread');
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

    # Check if requesting a 'all nodes sync'
    unless (@nodes)
    {
        my @needed_array;
        
        unless ($yes)
        {
            # Check if yesall is requested
            print "\nAre you requesting a synchronization for all nodes (y/n) ? ";
            my $answer = <STDIN>;
            chomp $answer;

            # Launching synchronization will all nodes
            if ($answer =~ /^y$/i)
            {
                launch_sync('all',\@registred_nodes,$max_threads);
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
            launch_sync('all',\@registred_nodes,$max_threads);
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
            unless ($yes)
            {
                # Showing list of node to be sync
                print "\nPuppets clients to be synchronized from the master :\n";
                foreach (@nodes_to_sync)
                {
                    print "$_\n";   
                }

                print "\nAre you sure do you want to continue (y/n) ? ";
                my $answer = <STDIN>;
                chomp $answer;
                if ($answer =~ /^y$/i)
                {
                    launch_sync($total_nodes_to_sync,\@nodes_to_sync,$max_threads);
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
            else
            {
                print "\nSynchronizing puppets clients with master :\n";
                launch_sync($total_nodes_to_sync,\@nodes_to_sync,$max_threads);
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

