#!/usr/bin/perl

# IP Accountant
# pedram amini <pedram@redhive.com, http://pedram.redhive.com>
#

use strict;

# configure these.
my $iptables    = "/usr/local/sbin/iptables";
my $rrdtool     = "/usr/local/sbin/rrdtool";
my $rrd_db_loc  = "/rrd/db";
my $html_report = "/www/redhive/ip_accountant_include.html";

my %INPUT  = ();
my %OUTPUT = ();

my ($key, $report_key, $report_count);

# we determine what "mode" we're in via the first argument.
#   rrd    - rrd updating mode
#   html   - html reporting mode
my $mode = shift;

# the default is to create a report in human readable form to stdout.
$mode = "default" if (!$mode);

if ($mode eq "default") {
    print "\n[ IP Accountant ]";
    print "\npedram amini";
    print "\npedram\@redhive.com, http://pedram.redhive.com\n";
}

my @iptables_input  = `$iptables -vxnL INPUT`;
my @iptables_output = `$iptables -vxnL OUTPUT`;


################################################################################
# load the /etc/hosts table
# 
my %hosts = ();
open (HOSTS, "/etc/hosts") || die "error opening /etc/hosts\n";

while (<HOSTS>) {
    chomp;      # remove newline.
    s/#.*//;    # remove comments.
    s/\s+/ /g;  # compress whitespace.
    s/^\s+//;   # remove leading whitespace.
    s/\s+$//;   # remove trailing whitespace.
    
    next if ( !$_ );
    
    # 0          1        2
    # ip_address hostname alias
    my @temp = split / /;
    $hosts{$temp[0]} = $temp[1];
}


################################################################################
# process the INPUT table
# 
# we start at 2 because the first 2 lines are part of the table header.
for (my $i = 2; $i <= $#iptables_input; $i++) {
    $_ = $iptables_input[$i];
    
    s/\s+/ /g;  # compress whitespace.
    s/^\s+//;   # remove leading whitespace.
    s/\s+$//;   # remove trailing whitespace.
    
    # 0    1     2      3    4   5  6   7      8
    # pkts bytes target prot opt in out source destination
    my @temp = split / /;
    if ( $hosts{$temp[8]} ) {
        $INPUT{$hosts{$temp[8]}} = $temp[1];
    }
}


################################################################################
# process the OUTPUT table
# 
# we start at 2 because the first 2 lines are part of the table header.
for (my $i = 2; $i <= $#iptables_output; $i++) {
    $_ = $iptables_output[$i];
    
    s/\s+/ /g;  # compress whitespace.
    s/^\s+//;   # remove leading whitespace.
    s/\s+$//;   # remove trailing whitespace.
    
    # 0    1     2      3    4   5  6   7      8
    # pkts bytes target prot opt in out source destination
    my @temp = split / /;
    if ( $hosts{$temp[7]} ) {
        $OUTPUT{$hosts{$temp[7]}} = $temp[1];
    }
}


################################################################################
# rrd update mode: update the rrd databases
#
if ($mode eq "rrd") {
    # the keys for INPUT and OUTPUT should be the same so we just step through
    # one of them. (DS order is rx:tx)
    foreach $key (sort keys %INPUT) {
        `$rrdtool update $rrd_db_loc/$key.rrd N:$INPUT{$key}:$OUTPUT{$key}`;
    }
}


################################################################################
# html reporting mode: generate an html report to the specified location
#
if ($mode eq "html") {
    open (HTML_REPORT, ">$html_report") || die "error opening $html_report\n";
    
    my $total_input   = 0;
    my $total_output  = 0;
    my $total_traffic = 0;
    
    # tally the totals. the keys for INPUT and OUTPUT should be the same so we 
    # just step through one of them.
    foreach $key (sort keys %INPUT) {
        $total_input  += $INPUT{$key};
        $total_output += $OUTPUT{$key};
    }
    
    $total_traffic = $total_input + $total_output;
    
    print HTML_REPORT <<END_OF_HEADER;
        <table border=0 cellpadding=1 cellspacing=0><tr><td bgcolor="#000000">
        <table border=0 cellpadding=10 cellspacing=1 bgcolor="#FFFFFF">
            <tr>
                <td><font face="arial" size=2><b>domain</b></font></td>
                <td align="center" colspan=2><font face="arial" size=2><b>input</b></font></td>
                <td align="center" colspan=2><font face="arial" size=2><b>output</b></font></td>
                <td align="center" colspan=2><font face="arial" size=2><b>total</b></font></td>
            </tr>
            <tr>
                <td><font face="arial" size=2><b>&nbsp;</b></font></td>
                <td><font face="arial" size=2><b>byte count</b></font></td>
                <td><font face="arial" size=2><b>% of input</b></font></td>
                <td><font face="arial" size=2><b>byte count</b></font></td>
                <td><font face="arial" size=2><b>% of output</b></font></td>
                <td><font face="arial" size=2><b>byte count</b></font></td>
                <td><font face="arial" size=2><b>% of total</b></font></td>
            </tr>
END_OF_HEADER

    foreach $key (sort keys %INPUT) {
        my $in_bytes    = convert_bytes($INPUT{$key});
        my $in_percent  = sprintf("%.2f", $INPUT{$key} / $total_input * 100);
        
        my $out_bytes   = convert_bytes($OUTPUT{$key});
        my $out_percent = sprintf("%.2f", $OUTPUT{$key} / $total_output * 100);
        
        my $tot_bytes   = convert_bytes($INPUT{$key} + $OUTPUT{$key});
        my $tot_percent = sprintf("%.2f", ($INPUT{$key} + $OUTPUT{$key}) / 
                                          $total_traffic * 100);
        print HTML_REPORT <<END_OF_ROW;
            <tr>
                <td align="left"><font face="arial" size=2><a href="http://$key">$key</a></font></td>
                <td align="right"><font face="arial" size=2>$in_bytes</font></td>
                <td align="right"><font face="arial" size=2>$in_percent%</font></td>
                <td align="right"><font face="arial" size=2>$out_bytes</font></td>
                <td align="right"><font face="arial" size=2>$out_percent%</font></td>
                <td align="right"><font face="arial" size=2>$tot_bytes</font></td>
                <td align="right"><font face="arial" size=2>$tot_percent%</font></td>
            </tr>
END_OF_ROW
    }

    $total_input   = convert_bytes($total_input);
    $total_output  = convert_bytes($total_output);
    $total_traffic = convert_bytes($total_traffic);
    
    print HTML_REPORT <<END_OF_FOOTER;
            <tr>
                <td align="left"><font face="arial" size=2><b>totals</b></font></td>
                <td align="right"><font face="arial" size=2><b>$total_input</b></font></td>
                <td align="right"><font face="arial" size=2><b>&nbsp;</b></font></td>
                <td align="right"><font face="arial" size=2><b>$total_output</b></font></td>
                <td align="right"><font face="arial" size=2><b>&nbsp;</b></font></td>
                <td align="right"><font face="arial" size=2><b>$total_traffic</b></font></td>
                <td align="right"><font face="arial" size=2><b>&nbsp;</b></font></td> 
            </tr>
        </table>
        </td></tr></table>
END_OF_FOOTER
}


################################################################################
# default mode: generate a human readable report to stdout
# 
if ($mode eq "default") {
    print "\n-- Input accounting --------------------------\n";
    foreach $key (sort keys %INPUT) {
        $report_key   = $key;
        $report_count = convert_bytes($INPUT{$key});
        write;
    }
    
    print "\n-- Output accounting -------------------------\n";
    foreach $key (sort keys %OUTPUT) {
        $report_key   = $key;
        $report_count = convert_bytes($OUTPUT{$key});
        write;
    }
}


################################################################################
# report format
# 
format STDOUT =
@<<<<<<<<<<<<<<<<<<<<<<<< @>>>>>>>>>>>>>>>>>>>
$report_key,              $report_count
.


################################################################################
# byte conversion function, converts bytes to a human readable form
# 
sub convert_bytes () {
    my $bytes = shift;
    
    my $kbytes = $bytes / 1024;

    return sprintf("%.2f GB", $kbytes / 1048576) if ($kbytes > 1048576);
    return sprintf("%.2f MB", $kbytes / 1024)    if ($kbytes > 1024);
    return sprintf("%.2f KB", $kbytes);
}
