#
#  78_FroniusSymJSON.pm
#

package main;

# Laden evtl. abhängiger Perl- bzw. FHEM-Module
use strict;
use warnings;
use Time::Local;
use POSIX qw( strftime );
use HttpUtils;
use JSON qw( decode_json );
#use 

sub FroniusSymJSON_Initialize($);
sub FroniusSymJSON_Define($$);
sub FroniusSymJSON_Undefine($$);
#sub FroniusSymJSON_Attr($@);
sub FroniusSymJSON_Set($$@);
sub FroniusSymJSON_Get($@);
sub FroniusSymJSON_GetUpdate($);
sub FroniusSymJSON_UpdateAborted($);

my $MODUL = "FroniusSymJSON";

my $unit_current = "W";
my $unit_day = "Wh";
my $unit_year = "Wh";
my $unit_total = "Wh";

# FHEM Modulfunktionen

sub ##########################################
FroniusSymJSON_Log($$$)
{
   my ( $hash, $loglevel, $text ) = @_;
   my $xline       = ( caller(0) )[2];
   
   my $xsubroutine = ( caller(1) )[3];
   my $sub         = ( split( ':', $xsubroutine ) )[2];
   $sub =~ s/FroniusSymJSON_//;

   my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
   Log3 $hash, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
}


sub FroniusSymJSON_Initialize($) {

    my ($hash) = @_;
    my $TYPE = "FroniusSymJSON";

    $hash->{DefFn}    = $TYPE . "_Define";
    $hash->{UndefFn}  = $TYPE . "_Undefine";
    $hash->{SetFn}    = $TYPE . "_Set";
    $hash->{GetFn}    = $TYPE . "_Get";
    $hash->{NotifyFn} = $TYPE . "_Notify";

    $hash->{NOTIFYDEV} = "global";

    $hash->{DbLog_splitFn}= $TYPE . "_DbLog_splitFn";
#    $hash->{AttrFn}       = $TYPE . "_Attr";


 $hash->{AttrList} = ""
    . "device_ids "
    . "disable:1,0 "
    . "interval "
    . "interval_night "
    . "unit_year:Wh,kWh,MWh,GWh "
    . "unit_total:Wh,kWh,MWh,GWh "
    . "unit_day:Wh,kWh,MWh,GWh "
    . "unit_current:W,kW,MW,GW "
    . "listdevices:1,0 "
    . "avoidDailyBug:1,0 "
    . $readingFnAttributes
  ;
} # end FroniusSymJSON_Initialize

sub FroniusSymJSON_Define($$) {

    my ($hash, $def) = @_;
    my @args = split("[ \t][ \t]*", $def);

    return "Usage: define <name> FroniusSymJSON <host>" if(@args <2 || @args >3);

    my $name = $args[0];
    my $type = "FroniusSymJSON";
    my $interval = 60;
    my $host = $args[2];

    $hash->{NAME} = $name;

    $hash->{STATE}    = "Initializing" if $interval > 0;
    $hash->{HOST}     = $host;
    $hash->{APIURL}   = "http://".$host."/solar_api/GetAPIVersion.cgi";
    $hash->{helper}{INTERVAL} = $interval;
    $hash->{MODEL}    = $type;
    
  #Clear Everything, remove all timers for this module
  RemoveInternalTimer($hash);
  
  # Get API Version after ten seconds. API Version is important as it also contains the Basis URL
  # for the API Calls.
  InternalTimer(gettimeofday() + 10, "FroniusSymJSON_getAPIVersion", $hash, 0);

  #
  # Init global variables for units from attr
  # InternalTimer(gettimeofday() + 10, "FroniusSymJSON_InitUnits", $hash, 0);

  #Reset temporary values
  #$hash->{fhem}{jsonInterpreter} = "";

  $hash->{fhem}{modulVersion} = '$Date: 2018-03-28 08:45:00 +0100 (Thu, 28 Mar 2018) $';
 
  return undef;
} #end FroniusSymJSON_Define

sub FroniusSymJSON_getAPIVersion($) {

	my ($hash) = @_;
	my $name = $hash->{NAME};

	FroniusSymJSON_Log($hash, 5, "$name: Getting API version and base url from $hash->{APIURL}");

	FroniusSymJSON_PerformHttpRequest($hash, $hash->{APIURL}, "API");
}

sub FroniusSymJSON_listDevices($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $rv = "1";

	my $listDevices = $attr{$name}{listdevices};
	if ($listDevices eq "1") {
		$rv = "1";
	} elsif ($listDevices eq "0") {
		$rv = "0";
	}
	return $rv;
}

sub FroniusSymJSON_getInterval($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $is_day = isday();

	my $interval = $attr{$name}{interval};
	# if there is no interval given, use the internal default
	if ($interval eq "") {
		# use default interval if none is given
		$interval = $hash->{helper}{INTERVAL};
	}
	
	# check if sun has gone. If yes and a night interval is set, use the night interval
	if ($is_day eq "0") {
		my $interval_night = $attr{$name}{interval_night};
		if ($interval_night ne "") {
			$interval = $interval_night;				
		}
	}

	# if interval is less then 5, we will use ten seconds as minimum
	if ($interval < 5) {
		# the minimum value
		$interval = 10;
		$attr{$name}{interval} = 10;
	}
	
	$hash->{helper}{last_used_interval} = $interval;
	$hash->{helper}{last_is_day} = $is_day;
	
	return $interval;
}

#
# Convert from one possible unit to another. Maybe not the most graceful way
# however, it works :-)
#
sub FroniusSymJSON_ConvertData($$$$) {
        my ($hash, $data, $sourceunit, $targetunit) = @_;
	my $name = $hash->{NAME};

	FroniusSymJSON_Log($hash, 5, "$name: Getting ConvertData for $data with source unit $sourceunit into targetunit $targetunit");

        my $rv;
        my @cv;

        $cv[0][0] = 'W';
        $cv[0][1] = 'kW';
        $cv[0][2] = 'MW';
        $cv[0][3] = 'GW';
        $cv[0][4] = 0.001;

        $cv[1][0] = 'GW';
        $cv[1][1] = 'MW';
        $cv[1][2] = 'kW';
        $cv[1][3] = 'W';
        $cv[1][4] = 1000;

        $cv[2][0] = 'Wh';
        $cv[2][1] = 'kWh';
        $cv[2][2] = 'MWh';
        $cv[2][3] = 'GWh';
        $cv[2][4] = 0.001;

        $cv[3][0] = 'GWh';
        $cv[3][1] = 'MWh';
        $cv[3][2] = 'kWh';
        $cv[3][3] = 'Wh';
        $cv[3][4] = 1000;

        my $i = 0;
        my $j = 0;
        my $sourceindex_dir = -1;
        my $sourceindex_val = -1;
        my $targetindex_dir = -1;
        my $targetindex_val = -1;
        my $isFinished = 0;
        while ($i < 4 && $isFinished == 0) {
                $j = 0;
                while ($j < 4) {
                        if ($cv[$i][$j] eq $sourceunit) {
                                $sourceindex_dir = $i;
                                $sourceindex_val = $j;
                        } elsif ($cv[$i][$j] eq $targetunit) {
                                $targetindex_dir = $i;
                                $targetindex_val = $j;
                        }
                        $j++;
                }
                if ($sourceindex_val < $targetindex_val && $sourceindex_val != -1 && $targetindex_val != -1) {
                        my $k = $sourceindex_val;
                        while ($k < $targetindex_val) {
                                $data = $data * $cv[$i][4];
                                $k++;
                        }
                        $isFinished = 1;
                }
                $i++;
        }

	FroniusSymJSON_Log($hash, 5, "$name: Getting ConvertData finished, new data $data with source unit $sourceunit into targetunit $targetunit");

        $rv = $data;
        return $rv;

}

#
# Prepare the http request to the Fronius system to get
# the Inverter Realtime Data
#
sub FroniusSymJSON_getInverterRealtimeData($) {

	my ($hash) = @_;
	my $name = $hash->{NAME};

	$hash->{STATE}    = "Receiving data";
	my $interval = FroniusSymJSON_getInterval($hash);

	FroniusSymJSON_Log($hash, 5, "$name: Getting InverterRealtimeData with scope SYSTEM, interval: $interval, sunrise: ".sunrise().", isday():".isday());

	if ($hash->{BaseURL} ne "") {

	   FroniusSymJSON_PerformHttpRequest($hash, $hash->{BaseURL}."GetInverterRealtimeData.cgi?Scope=System", "GetInverterRealtimeData");

	   # Now add a timer for getting the data
	   InternalTimer(gettimeofday() + $interval, "FroniusSymJSON_getInverterRealtimeData", $hash, 0);

	} else {
	   # Error, handling required
	   # TODO
	   FroniusSymJSON_Log($hash, 1, "$name: Getting API version and base url from $hash->{APIURL}");
	}
}

#
# Perform the http request as a non-blocking request
#
sub FroniusSymJSON_PerformHttpRequest($$)
{
    my ($hash, $url, $callname) = @_;
    my $name = $hash->{NAME};
    my $param = {
                    url        => $url,
                    timeout    => 5,
                    hash       => $hash,                                                                                 # Muss gesetzt werden, damit die Callback funktion wieder $hash hat
                    method     => "GET",                                                                                 # Lesen von Inhalten
                    header     => "User-Agent: FroniusSymJSON/1.0.0\r\nAccept: application/json",                            # Den Header gemäß abzufragender Daten ändern
                    callback   => \&FroniusSymJSON_ParseHttpResponse,                                                    # Diese Funktion soll das Ergebnis dieser HTTP Anfrage bearbeiten
                    call       => $callname
                };

    FroniusSymJSON_Log($hash, 5, "$name: Executing non-blocking get for $url");

    HttpUtils_NonblockingGet($param);                                                                                    # Starten der HTTP Abfrage. Es gibt keinen Return-Code. 
}

sub FroniusSymJSON_ParseHttpResponse($)
{
    my ($param, $err, $data) = @_;
    my $hash = $param->{hash};
    my $name = $hash->{NAME};
    my $interval = FroniusSymJSON_getInterval($hash);

    if($err ne "")                                                                                                      # wenn ein Fehler bei der HTTP Abfrage aufgetreten ist
    {
        FroniusSymJSON_Log($hash, 1, "error while requesting ".$param->{url}." - $err");                                            # Eintrag fürs Log
	if ($param->{call} eq "API") {
	  #
	  # if API Call failed, try again in 60 seconds
	  #
	  InternalTimer(gettimeofday() + 60, "FroniusSymJSON_getAPIVersion", $hash, 0);
    	  $hash->{STATE}    = "Connection error getting API info";
          FroniusSymJSON_Log($hash, 1, "API call to DataLogger failed");                                                         # Eintrag fürs Log
	} elsif ($param->{call} eq "GetInverterRealtimeData") {
    	  $hash->{STATE}    = "Connection error getting DATA";
          FroniusSymJSON_Log($hash, 1, "Data call to DataLogger failed");                                                         # Eintrag fürs Log
	}
    }
    elsif($data ne "")                                                                                                  # wenn die Abfrage erfolgreich war ($data enthält die Ergebnisdaten des HTTP Aufrufes)
    {
        FroniusSymJSON_Log($hash, 5, "url ".$param->{url}." returned: $data");                                                         # Eintrag fürs Log

	my $avoidDailyBug = 0;
	if (defined $attr{$name}{avoidDailyBug}) {
		$avoidDailyBug = $attr{$name}{avoidDailyBug};
	}

	if ($param->{call} eq "API") {

	        FroniusSymJSON_Log($hash, 5, "API was checked");                                                         # Eintrag fürs Log

		my $json = decode_json($data);
	
		$hash->{APIVersion} = $json->{'APIVersion'};
		$hash->{BaseURL} = "http://".$hash->{HOST}.$json->{'BaseURL'};
		$hash->{CompatibilityRange} = $json->{'CompatibilityRange'};
		
		$hash->{STATE}    = "Initialised";

		# After the API Request all internal timers could be removed.
		RemoveInternalTimer($hash);
	
		# Now add a timer for getting the data
		InternalTimer(gettimeofday() + $interval, "FroniusSymJSON_getInverterRealtimeData", $hash, 0);
		
	} elsif ($param->{call} eq "GetInverterRealtimeData") {
	        FroniusSymJSON_Log($hash, 5, "GetInverterRealtimeData");                                                         # Eintrag fürs Log

		my $json = decode_json($data);
		
		my $device_ids = $attr{$name}{device_ids};
		if ($device_ids eq "") {
		  $device_ids = "1";
		}

		my $laststatuscode = "";
		my $laststatusreason = "";
		my $laststatususermsg = "";
		my $lasttimestamp = "";

		my $totalenergy_sum = 0;
		my $yearenergy_sum = 0;
		my $dayenergy_sum = 0;
		my $currentenergy_sum = 0;
		
		
		my $rv = 0;
		
		my @devices = split /:/, $device_ids;
		#
		# Iterate through all defined device IDs
		#
		foreach my $device_id ( @devices ) {
			
			FroniusSymJSON_Log($hash, 5, "DeviceID: $device_id"); 

			#
			# Important to read this as first value to be able to consider the avoidDailyBug setting
			#
			my $dayenergy = $json->{'Body'}->{'Data'}->{'DAY_ENERGY'}->{'Values'}->{$device_id};
			my $dayunit = $json->{'Body'}->{'Data'}->{'DAY_ENERGY'}->{'Unit'};
			$dayenergy = FroniusSymJSON_ConvertData($hash, $dayenergy, $dayunit, $unit_day);

			my $totalenergy = $json->{'Body'}->{'Data'}->{'TOTAL_ENERGY'}->{'Values'}->{$device_id};
			my $totalunit = $json->{'Body'}->{'Data'}->{'TOTAL_ENERGY'}->{'Unit'};
			$totalenergy = FroniusSymJSON_ConvertData($hash, $totalenergy, $totalunit, $unit_total);

			my $yearenergy = $json->{'Body'}->{'Data'}->{'YEAR_ENERGY'}->{'Values'}->{$device_id};
			my $yearunit = $json->{'Body'}->{'Data'}->{'YEAR_ENERGY'}->{'Unit'};
			$yearenergy = FroniusSymJSON_ConvertData($hash, $yearenergy, $yearunit, $unit_year);

			my $currentenergy = $json->{'Body'}->{'Data'}->{'PAC'}->{'Values'}->{$device_id};
			my $currentunit = $json->{'Body'}->{'Data'}->{'PAC'}->{'Unit'};
			$currentenergy = FroniusSymJSON_ConvertData($hash, $currentenergy, $currentunit, $unit_current);
			
			$totalenergy_sum = $totalenergy_sum + $totalenergy;
			$yearenergy_sum = $yearenergy_sum + $yearenergy;
			$dayenergy_sum = $dayenergy_sum + $dayenergy;
			$currentenergy_sum = $currentenergy_sum + $currentenergy;


			$laststatuscode = $json->{'Head'}->{'Status'}->{'Code'};
			$laststatusreason = $json->{'Head'}->{'Status'}->{'Reason'};
			$laststatususermsg = $json->{'Head'}->{'Status'}->{'UserMessage'};
			$lasttimestamp = $json->{'Head'}->{'Timestamp'};

			# it can be turned of to log each single device. This makes especially sense if
			# only one device exists
			if (FroniusSymJSON_listDevices($hash) eq "1") {
				
				# For the devices the method is only necessary if the data for the devices
				# should be stored
				
				# There is a bug in DAY_ENERGY. DAY_ENERGY stopps counting even though YEAR_ENERGY and TOTAL_ENERGY
				# are counted correctly - or at least counting is continued for them ;-)
				# It is possible to use an attribute to define that the DAY_ENERGY should not be taken from the
				# JSON response. Instead it will be calculated based on the YEAR_ENERGY.
				if ($avoidDailyBug == 1) {
					# First it is required to convert the year value into the same unit as the day unit.
					# Here the configured unit is the base because the $yearenergy has already been converted
					# to the $unit_year unit.
					my $tmp_yearenergy = FroniusSymJSON_ConvertData($hash, $yearenergy, $unit_year, $unit_day);
					# Read the current value from the stored reading
					my $last_yearenergy = ReadingsVal($name, "ENERGY_YEAR_".$device_id, 0);
					FroniusSymJSON_Log($hash, 5, "GetInverterRealtimeData: Received $last_yearenergy from reading");
					# convert it into the unit used for $unit_day.
					# IN CASE the unit has been changed in fhem since between two updated, this will lead to an
					# incorrect value!
					$last_yearenergy = FroniusSymJSON_ConvertData($hash, $last_yearenergy, $unit_year, $unit_day);

					# $tmp_dayenergy is only required to make a log entry...
					my $tmp_dayenergy = $dayenergy;

					$dayenergy = $tmp_yearenergy - $last_yearenergy;
					FroniusSymJSON_Log($hash, 5, "GetInverterRealtimeData: Avoiding bug, using calculated value of $dayenergy instead of read value of $tmp_dayenergy");
				}

				readingsBeginUpdate($hash);
				$rv = readingsBulkUpdate($hash, "ENERGY_DAY_".$device_id, $dayenergy);
				$rv = readingsBulkUpdate($hash, "ENERGY_CURRENT_".$device_id, $currentenergy);
				$rv = readingsBulkUpdate($hash, "ENERGY_TOTAL_".$device_id, $totalenergy);
				$rv = readingsBulkUpdate($hash, "ENERGY_YEAR_".$device_id, $yearenergy);
				readingsEndUpdate($hash, 1);
			}
		}

		if ($avoidDailyBug == 1) {
			my $tmp_day_begin = ReadingsVal($name, "YEAR_SUM_TODAY_START", "0:unknown");
			my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

			my $tmp_year_begin_sum;
			my @begin_info = split /:/, $tmp_day_begin;

			if ($begin_info[1] eq $wday) {
				$tmp_year_begin_sum = $begin_info[0];
			} else {
				$tmp_year_begin_sum = FroniusSymJSON_ConvertData($hash, $yearenergy_sum, $unit_year, $unit_day);
				readingsSingleUpdate($hash, "YEAR_SUM_TODAY_START", $tmp_year_begin_sum.":".$wday, undef);
			}
			
			# First it is required to convert the year value into the same unit as the day unit.
			# Here the configured unit is the base because the $yearenergy has already been converted
			# to the $unit_year unit.
			my $tmp_yearenergy_sum = FroniusSymJSON_ConvertData($hash, $yearenergy_sum, $unit_year, $unit_day);
			FroniusSymJSON_Log($hash, 5, "GetInverterRealtimeData: Current yearenergy value is $tmp_yearenergy_sum $unit_day");

			# $tmp_dayenergy is only required to make a log entry...
			my $tmp_dayenergy_sum = $dayenergy_sum;

			$dayenergy_sum = $tmp_yearenergy_sum - $tmp_year_begin_sum;
			FroniusSymJSON_Log($hash, 5, "GetInverterRealtimeData: Avoiding bug, using calculated value of $dayenergy_sum instead of read value of $tmp_dayenergy_sum");
		}


		readingsBeginUpdate($hash);
		$rv = readingsBulkUpdate($hash, "ENERGY_DAY_SUM", $dayenergy_sum);
		$rv = readingsBulkUpdate($hash, "ENERGY_CURRENT_SUM", $currentenergy_sum);
		$rv = readingsBulkUpdate($hash, "ENERGY_TOTAL_SUM", $totalenergy_sum);
		$rv = readingsBulkUpdate($hash, "ENERGY_YEAR_SUM", $yearenergy_sum);
		$rv = readingsBulkUpdate($hash, "Status_Code", $laststatuscode);
		$rv = readingsBulkUpdate($hash, "Status_Reason", $laststatusreason);
		$rv = readingsBulkUpdate($hash, "Status_UserMessage", $laststatususermsg);
		$rv = readingsBulkUpdate($hash, "Response_timestamp", $lasttimestamp);
		readingsEndUpdate($hash, 1);
		
		#my @values = $json->{'Body'}->{'Data'}->{'TOTAL_ENERGY'}->{'Values'};
		#foreach my $singlevalue ( @values ) {
		#	FroniusSymJSON_Log($hash, 1, "GetInverterRealtimeData: $singlevalue"); 
		#}
	}
    }
    
    # Damit ist die Abfrage zuende.
    # Evtl. einen InternalTimer neu schedulen
}

sub FroniusSymJSON_DbLog_splitFn($) {
  my ($event) = @_;
  my ($reading, $value, $unit) = "";
#  my $hash = $event->{hash};
#  my $name = $hash->{NAME};

  my @parts = split(/ /,$event,3);
  $reading = $parts[0];
  $reading =~ tr/://d;
  $value = $parts[1];
  
  $unit = "";
  $unit = $unit_day if($reading =~ /ENERGY_DAY.*/);;
  $unit = $unit_current if($reading =~ /ENERGY_CURRENT.*/);;
  $unit = $unit_total if($reading =~ /ENERGY_TOTAL.*/);;
  $unit = $unit_year if($reading =~ /ENERGY_YEAR.*/);  

  Log3 "dbsplit", 5, "FroniusSymJSON dbsplit: ".$event."  $reading: $value $unit" if(defined($value));
  Log3 "dbsplit", 5, "FroniusSymJSON dbsplit: ".$event."  $reading" if(!defined($value));

  return ($reading, $value, $unit);
}


sub FroniusSymJSON_Set($$@) {
}

sub FroniusSymJSON_Get($@) {
}

sub FroniusSymJSON_Undefine($$) {
  my ($hash, $args) = @_;

  RemoveInternalTimer($hash);

  BlockingKill($hash->{helper}{RUNNING_PID}) if(defined($hash->{helper}{RUNNING_PID}));

  return undef;
} # end FroniusSymJSON_Undefine


sub FroniusSymJSON_Notify($$)
{
	my ($own_hash, $dev_hash) = @_;
	my $ownName = $own_hash->{NAME}; # own name / hash

	FroniusSymJSON_Log $own_hash, 5, "Getting notify $ownName / $dev_hash->{NAME}";
 
	return "" if(IsDisabled($ownName)); # Return without any further action if the module is disabled
 
	my $devName = $dev_hash->{NAME}; # Device that created the events
	my $events = deviceEvents($dev_hash, 1);

	if($devName eq "global" && grep(m/^INITIALIZED|REREADCFG$/, @{$events}))
	{
		 FroniusSymJSON_InitUnits($own_hash);
	}
}

sub FroniusSymJSON_InitUnits($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	FroniusSymJSON_Log $hash, 1, "Initialising global units for $name";
	
	if ($init_done) {
		if (defined $attr{$name}{unit_day}) {
			$unit_day = $attr{$name}{unit_day};
		} else {
			$unit_day = "Wh";
			FroniusSymJSON_Log $hash, 1, "attr unit_day not set, using default";
		}
		if (defined $attr{$name}{unit_current}) {
			$unit_current = $attr{$name}{unit_current};
		} else {
			$unit_current = "W";
			FroniusSymJSON_Log $hash, 1, "attr unit_current not set, using default";
		}
		if (defined $attr{$name}{unit_total}) {
			$unit_total = $attr{$name}{unit_total};
		} else {
			$unit_total = "Wh";
			FroniusSymJSON_Log $hash, 1, "attr unit_total not set, using default";
		}
		if (defined $attr{$name}{unit_year}) {
			$unit_year =  $attr{$name}{unit_year};
		} else {
			$unit_year =  "Wh";
			FroniusSymJSON_Log $hash, 1, "attr unit_year not set, using default";
		}
		FroniusSymJSON_Log $hash, 1, "Global units initialised for $name";
	} else {
		FroniusSymJSON_Log $hash, 1, "Fhem not ready yet, retry in 5 seconds";
	  	InternalTimer(gettimeofday() + 5, "FroniusSymJSON_InitUnits", $hash, 0);
	}
}

sub ##########################################
FroniusSymJSON_GetUpdate($) {

}

sub ############################
FroniusSymJSON_UpdateAborted($)
{
  my ($hash) = @_;
  delete($hash->{helper}{RUNNING_PID});
  my $name = $hash->{NAME};
  my $host = $hash->{HOST};
  FroniusSymJSON_Log $hash, 1, "Timeout when connecting to host $host";

} # end FroniusSymJSON_UpdateAborted

# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item [helper|device|command]
=item summary Kurzbeschreibung in Englisch was FroniusSymJSON steuert/unterstützt
=item summary_DE Kurzbeschreibung in Deutsch was FroniusSymJSON steuert/unterstützt

=begin html
 Englische Commandref in HTML
=end html

=begin html_DE
 Deustche Commandref in HTML
=end html

# Ende der Commandref
=cut
