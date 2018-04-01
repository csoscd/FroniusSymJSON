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

my $request_CommonInverterData = 0;
my $request_LoggerLEDInfo = 0;
my $request_MinMaxInverterData = 0;
my $request_SystemCumulationInverterData = 1;

# FHEM Modulfunktionen

#
# Helper Function to check if a string begins with a specific suffix
#
sub FroniusSymJSON_Begins_With
{
	if (length($_[0]) >= length($_[1])) {
    	return substr($_[0], 0, length($_[1])) eq $_[1];
	} else {
		return 0;
	}
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
# Get error text for fronius error code. Only a few are implemented.
#
sub FroniusSymJSON_ErrorCodeToText($) {
	my ( $errorcode ) = @_;
	my $rv = "unknown";
	
	if ($errorcode eq "0") {
		$rv = "Ok";
	} elsif ($errorcode eq "306") {
		$rv = "DC/AC Power Low";
	} elsif ($errorcode eq "307") {
		$rv = "DC Voltage Low";
	}
	
	
	return $rv;
}

#
# Get status text from fronius status code.
# 
sub FroniusSymJSON_StatusCodeToText($) {
	my ( $errorcode ) = @_;
	my $rv = "unknown";
	
	if ($errorcode eq "0" || $errorcode eq "1" || $errorcode eq "2" || $errorcode eq "3" || $errorcode eq "4" || $errorcode eq "5" || $errorcode eq "6") {
		$rv = "Startup";
	} elsif ($errorcode eq "7") {
		$rv = "Running";
	} elsif ($errorcode eq "8") {
		$rv = "Standby";
	} elsif ($errorcode eq "9") {
		$rv = "Bootloading";
	} elsif ($errorcode eq "10") {
		$rv = "Error";
	}
	
	
	return $rv;
}

#
# Helper function to extract the device ID from the internal call parameter.
#
sub FroniusSymJSON_GetDeviceIdFromCall($) {
	my ( $call ) = @_;
	my $rv = "-1";
	
	# Just make sure the parameter contains a ":". Only in this
	# case we have the right param and could extract the device Id.
	if (index($call, ":") != -1) {
		my @params = split /:/, $call;
		$rv = $params[1]
	}
	
	return $rv;
}

#
# Help Function to have a standard logging
#
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
    . "Request_CommonInverterData:1,0 "
    . "Request_LoggerLEDInfo:1,0 "
    . "Request_MinMaxInverterData:1,0 "
    . "Request_SystemCumulationInverterData:1,0 "
#    . ":1,0 "
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
  # InternalTimer(gettimeofday() + 10, "FroniusSymJSON_InitAttr", $hash, 0);

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


sub FroniusSymJSON_GetCommonInverterData($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	$hash->{STATE}    = "Receiving data";
	my $interval = FroniusSymJSON_getInterval($hash);

	FroniusSymJSON_Log($hash, 5, "$name: FroniusSymJSON_GetCommonInverterData with scope device, interval: $interval, sunrise: ".sunrise().", isday():".isday());

	if ($hash->{BaseURL} ne "") {

		my $device_ids = $attr{$name}{device_ids};
		my @devices = split /:/, $device_ids;
		#
		# Iterate through all defined device IDs
		#
		foreach my $device_id ( @devices ) {

			FroniusSymJSON_Log($hash, 5, "Making GetCommonInverterData http call for DeviceID: $device_id"); 

			FroniusSymJSON_PerformHttpRequest($hash, $hash->{BaseURL}."GetInverterRealtimeData.cgi?Scope=Device&DeviceId=".$device_id."&DataCollection=CommonInverterData", "GetCommonInverterData:".$device_id);
		}

	} else {
	   # Error, handling required
	   # TODO
	   FroniusSymJSON_Log($hash, 1, "$name: Getting API version and base url from $hash->{APIURL}");
	}

	# Now add a timer for getting the data
	InternalTimer(gettimeofday() + $interval, "FroniusSymJSON_GetCommonInverterData", $hash, 0);

}

sub FroniusSymJSON_GetCommonInverterData_Parse($$$) {
	my ($hash, $data, $call) = @_;
	my $name = $hash->{NAME};

	my $rv = 0;

	my $json = decode_json($data);

	my $deviceid = FroniusSymJSON_GetDeviceIdFromCall($call);

	FroniusSymJSON_Log($hash, 5, "Processing Parse_GetCommonInverterData for device ".$deviceid);                                                         # Eintrag fürs Log
	
	my $ENERGY_FAC = 0;
	my $ENERGY_IAC = 0;
	my $ENERGY_IDC = 0;
	my $ENERGY_PAC = 0;
	my $ENERGY_UAC = 0;
	my $ENERGY_UDC = 0;
	
	my $LAST_TIMESTAMP = 0;
	
	my $Device_ErrorCode = 0;
	my $Device_ErrorText = "-";
	my $Device_StatusCode = 0;
    my $Device_StatusText = "-";

	if (defined $json->{'Body'}->{'Data'}->{'FAC'}->{'Value'}) {
		$ENERGY_FAC = $json->{'Body'}->{'Data'}->{'FAC'}->{'Value'}." ".$json->{'Body'}->{'Data'}->{'FAC'}->{'Unit'};
	}
	
	if (defined $json->{'Body'}->{'Data'}->{'IAC'}->{'Value'}) {
		$ENERGY_IAC = $json->{'Body'}->{'Data'}->{'IAC'}->{'Value'}." ".$json->{'Body'}->{'Data'}->{'IAC'}->{'Unit'};
	}

	if (defined $json->{'Body'}->{'Data'}->{'IDC'}->{'Value'}) {
		$ENERGY_IDC = $json->{'Body'}->{'Data'}->{'IDC'}->{'Value'}." ".$json->{'Body'}->{'Data'}->{'IDC'}->{'Unit'};
	}

	if (defined $json->{'Body'}->{'Data'}->{'PAC'}->{'Value'}) {
		$ENERGY_PAC = $json->{'Body'}->{'Data'}->{'PAC'}->{'Value'}." ".$json->{'Body'}->{'Data'}->{'PAC'}->{'Unit'};
	}

	if (defined $json->{'Body'}->{'Data'}->{'UAC'}->{'Value'}) {
		$ENERGY_UAC = $json->{'Body'}->{'Data'}->{'UAC'}->{'Value'}." ".$json->{'Body'}->{'Data'}->{'UAC'}->{'Unit'};
	}

	if (defined $json->{'Body'}->{'Data'}->{'UDC'}->{'Value'}) {
		$ENERGY_UDC = $json->{'Body'}->{'Data'}->{'UDC'}->{'Value'}." ".$json->{'Body'}->{'Data'}->{'UDC'}->{'Unit'};
	}
	

	$Device_ErrorCode = $json->{'Body'}->{'Data'}->{'DeviceStatus'}->{'ErrorCode'};
	$Device_ErrorText = FroniusSymJSON_ErrorCodeToText($Device_ErrorCode);
	$Device_StatusCode = $json->{'Body'}->{'Data'}->{'DeviceStatus'}->{'StatusCode'};
	$Device_StatusText = FroniusSymJSON_StatusCodeToText($Device_StatusCode);

	$LAST_TIMESTAMP = $json->{'Head'}->{'Timestamp'};

	readingsBeginUpdate($hash);
	$rv = readingsBulkUpdate($hash, "FAC_CID_".$deviceid, $ENERGY_FAC);
	$rv = readingsBulkUpdate($hash, "IAC_CID_".$deviceid, $ENERGY_IAC);
	$rv = readingsBulkUpdate($hash, "IDC_CID_".$deviceid, $ENERGY_IDC);
	$rv = readingsBulkUpdate($hash, "PAC_CID_".$deviceid, $ENERGY_PAC);
	$rv = readingsBulkUpdate($hash, "UAC_CID_".$deviceid, $ENERGY_UAC);
	$rv = readingsBulkUpdate($hash, "UDC_CID_".$deviceid, $ENERGY_UDC);
	$rv = readingsBulkUpdate($hash, "ErrorCode_CID_".$deviceid, $Device_ErrorCode);
	$rv = readingsBulkUpdate($hash, "ErrorText_CID_".$deviceid, $Device_ErrorText);
	$rv = readingsBulkUpdate($hash, "StatusCode_CID_".$deviceid, $Device_StatusCode);
	$rv = readingsBulkUpdate($hash, "StatusText_CID_".$deviceid, $Device_StatusText);
	$rv = readingsBulkUpdate($hash, "Timestamp_CID_".$deviceid, $LAST_TIMESTAMP);
	readingsEndUpdate($hash, 1);
}

sub FroniusSymJSON_GetLoggerLEDInfo($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	$hash->{STATE}    = "Receiving data";
	my $interval = FroniusSymJSON_getInterval($hash);

	FroniusSymJSON_Log($hash, 5, "$name: FroniusSymJSON_GetLoggerLEDInfo with scope device, interval: $interval, sunrise: ".sunrise().", isday():".isday());

	if ($hash->{BaseURL} ne "") {
		FroniusSymJSON_Log($hash, 5, "Making GetLoggerLEDInfo http call"); 
		FroniusSymJSON_PerformHttpRequest($hash, $hash->{BaseURL}."GetLoggerLEDInfo.cgi", "GetLoggerLEDInfo");
	} else {
	   # Error, handling required
	   # TODO
	   FroniusSymJSON_Log($hash, 1, "$name: Getting API version and base url from $hash->{APIURL}");
	}

	# Now add a timer for getting the data
	InternalTimer(gettimeofday() + $interval, "FroniusSymJSON_GetLoggerLEDInfo", $hash, 0);
}

sub FroniusSymJSON_GetLoggerLEDInfo_Parse($$) {
	my ($hash, $data) = @_;
	my $name = $hash->{NAME};
	FroniusSymJSON_Log($hash, 5, "Parse_GetLoggerLEDInfo");                                                         # Eintrag fürs Log

	my $json = decode_json($data);

	my $device_ids = $attr{$name}{device_ids};
	if ($device_ids eq "") {
	  $device_ids = "1";
	}

}

sub FroniusSymJSON_GetMinMaxInverterData($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	$hash->{STATE}    = "Receiving data";
	my $interval = FroniusSymJSON_getInterval($hash);

	FroniusSymJSON_Log($hash, 5, "$name: FroniusSymJSON_GetMinMaxInverterData with scope device, interval: $interval, sunrise: ".sunrise().", isday():".isday());

	if ($hash->{BaseURL} ne "") {

		my $device_ids = $attr{$name}{device_ids};
		my @devices = split /:/, $device_ids;
		#
		# Iterate through all defined device IDs
		#
		foreach my $device_id ( @devices ) {

			FroniusSymJSON_Log($hash, 4, "Making GetMinMaxInverterData http call for DeviceID: $device_id"); 

			FroniusSymJSON_PerformHttpRequest($hash, $hash->{BaseURL}."GetInverterRealtimeData.cgi?Scope=Device&DeviceId=".$device_id."&DataCollection=MinMaxInverterData", "GetMinMaxInverterData:".$device_id);
		}


	} else {
	   # Error, handling required
	   # TODO
	   FroniusSymJSON_Log($hash, 1, "$name: Getting API version and base url from $hash->{APIURL}");
	}

	# Now add a timer for getting the data
	InternalTimer(gettimeofday() + $interval, "FroniusSymJSON_GetMinMaxInverterData", $hash, 0);
}

sub FroniusSymJSON_GetMinMaxInverterData_Parse($$$) {
	my ($hash, $data, $call) = @_;
	my $name = $hash->{NAME};
	FroniusSymJSON_Log($hash, 5, "Parse_GetMinMaxInverterData");                                                         # Eintrag fürs Log

	my $json = decode_json($data);

	my $device_ids = $attr{$name}{device_ids};
	if ($device_ids eq "") {
	  $device_ids = "1";
	}

}

#
# Prepare the http request to the Fronius system to get
# the Inverter Realtime Data
#
sub FroniusSymJSON_GetInverterRealtimeData($) {

	my ($hash) = @_;
	my $name = $hash->{NAME};

	$hash->{STATE}    = "Receiving data";
	my $interval = FroniusSymJSON_getInterval($hash);

	FroniusSymJSON_Log($hash, 5, "$name: Getting InverterRealtimeData with scope SYSTEM, interval: $interval, sunrise: ".sunrise().", isday():".isday());

	if ($hash->{BaseURL} ne "") {

	   FroniusSymJSON_PerformHttpRequest($hash, $hash->{BaseURL}."GetInverterRealtimeData.cgi?Scope=System", "GetInverterRealtimeData");

	   # Now add a timer for getting the data
	   InternalTimer(gettimeofday() + $interval, "FroniusSymJSON_GetInverterRealtimeData", $hash, 0);

	} else {
	   # Error, handling required
	   # TODO
	   FroniusSymJSON_Log($hash, 1, "$name: Getting API version and base url from $hash->{APIURL}");
	}
}


sub FroniusSymJSON_GetInverterRealtimeData_Parse($$) {
	my ($hash, $data) = @_;
	my $name = $hash->{NAME};
	FroniusSymJSON_Log($hash, 5, "Parse_GetInverterRealtimeData");                                                         # Eintrag fürs Log

	my $json = decode_json($data);

	my $device_ids = $attr{$name}{device_ids};
	if ($device_ids eq "") {
	  $device_ids = "1";
	}

	my $avoidDailyBug = 0;
	if (defined $attr{$name}{avoidDailyBug}) {
		$avoidDailyBug = $attr{$name}{avoidDailyBug};
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

			my $energy_day_read_dev = $dayenergy;

			# There is a bug in DAY_ENERGY. DAY_ENERGY stopps counting even though YEAR_ENERGY and TOTAL_ENERGY
			# are counted correctly - or at least counting is continued for them ;-)
			# It is possible to use an attribute to define that the DAY_ENERGY should not be taken from the
			# JSON response. Instead it will be calculated based on the YEAR_ENERGY.
			if ($avoidDailyBug == 1) {

				my $year_today_start_dev = ReadingsVal($name, "YEAR_TODAY_START_".$device_id, "0:unknown");
				my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

				my $tmp_year_begin_dev;
				my @begin_info = split /:/, $year_today_start_dev;

				if ($begin_info[1] eq $wday) {
					$tmp_year_begin_dev = $begin_info[0];
				} else {
					$tmp_year_begin_dev = FroniusSymJSON_ConvertData($hash, $yearenergy, $unit_year, $unit_day);
					readingsSingleUpdate($hash, "YEAR_TODAY_START_".$device_id, $tmp_year_begin_dev.":".$wday, undef);
				}

				# First it is required to convert the year value into the same unit as the day unit.
				# Here the configured unit is the base because the $yearenergy has already been converted
				# to the $unit_year unit.
				my $tmp_yearenergy_dev = FroniusSymJSON_ConvertData($hash, $yearenergy, $unit_year, $unit_day);
				FroniusSymJSON_Log($hash, 5, "GetInverterRealtimeData_Parse: Current yearenergy value for device $device_id is $tmp_yearenergy_dev $unit_day");

				$dayenergy = $tmp_yearenergy_dev - $tmp_year_begin_dev;
				FroniusSymJSON_Log($hash, 5, "GetInverterRealtimeData_Parse: Avoiding bug, using calculated value of $dayenergy instead of read value of $energy_day_read_dev");
			}

			readingsBeginUpdate($hash);
			if ($avoidDailyBug == 1) {
				$rv = readingsBulkUpdate($hash, "ENERGY_DAY_READ_".$device_id, $energy_day_read_dev);
			}
			$rv = readingsBulkUpdate($hash, "ENERGY_DAY_".$device_id, $dayenergy);
			$rv = readingsBulkUpdate($hash, "ENERGY_CURRENT_".$device_id, $currentenergy);
			$rv = readingsBulkUpdate($hash, "ENERGY_TOTAL_".$device_id, $totalenergy);
			$rv = readingsBulkUpdate($hash, "ENERGY_YEAR_".$device_id, $yearenergy);
			readingsEndUpdate($hash, 1);
		}
	}

	my $energy_day_read_sum = $dayenergy_sum;

	if ($avoidDailyBug == 1) {
		my $year_sum_today_start = ReadingsVal($name, "YEAR_SUM_TODAY_START", "0:unknown");
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

		my $tmp_year_begin_sum;
		my @begin_info = split /:/, $year_sum_today_start;

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
		FroniusSymJSON_Log($hash, 5, "Parse_GetInverterRealtimeData: Current yearenergy value is $tmp_yearenergy_sum $unit_day");

		$dayenergy_sum = $tmp_yearenergy_sum - $tmp_year_begin_sum;
		FroniusSymJSON_Log($hash, 5, "Parse_GetInverterRealtimeData: Avoiding bug, using calculated value of $dayenergy_sum instead of read value of $energy_day_read_sum");
	}


	readingsBeginUpdate($hash);
	if ($avoidDailyBug == 1) {
		$rv = readingsBulkUpdate($hash, "ENERGY_DAY_READ_SUM", $energy_day_read_sum);
	}
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

		if ($param->{call} eq "API") {
	
		        FroniusSymJSON_Log($hash, 5, "API was checked");                                                         # Eintrag fürs Log
	
			my $json = decode_json($data);
		
			$hash->{APIVersion} = $json->{'APIVersion'};
			$hash->{BaseURL} = "http://".$hash->{HOST}.$json->{'BaseURL'};
			$hash->{CompatibilityRange} = $json->{'CompatibilityRange'};
			
			$hash->{STATE}    = "Initialised";
	
			# After the API Request all internal timers could be removed.
			RemoveInternalTimer($hash);
		
			if ($request_SystemCumulationInverterData eq "1") {
				# Now add a timer for getting the data
				InternalTimer(gettimeofday() + $interval, "FroniusSymJSON_GetInverterRealtimeData", $hash, 0);
			}
			if ($request_MinMaxInverterData eq "1") {
				# Now add a timer for getting the data
				InternalTimer(gettimeofday() + ($interval + 1), "FroniusSymJSON_GetMinMaxInverterData", $hash, 0);
			}
			if ($request_LoggerLEDInfo eq "1") {
				# Now add a timer for getting the data
				InternalTimer(gettimeofday() + ($interval + 2), "FroniusSymJSON_GetLoggerLEDInfo", $hash, 0);
			}
			if ($request_CommonInverterData eq "1") {
				# Now add a timer for getting the data
				InternalTimer(gettimeofday() + ($interval + 3), "FroniusSymJSON_GetCommonInverterData", $hash, 0);
			}		
		} elsif ($param->{call} eq "GetInverterRealtimeData") {
			#
			# This is scope = system
			# 
			FroniusSymJSON_GetInverterRealtimeData_Parse($hash, $data);
		} elsif (FroniusSymJSON_Begins_With($param->{call}, "GetCommonInverterData")) {
			#
			# This is scope = device
			#
			FroniusSymJSON_GetCommonInverterData_Parse($hash, $data, $param->{call});
		} elsif (FroniusSymJSON_Begins_With($param->{call}, "GetMinMaxInverterData")) {
			#
			# This is Scope = device
			#
			FroniusSymJSON_GetMinMaxInverterData_Parse($hash, $data, $param->{call});
		} elsif ($param->{call} eq "GetLoggerLEDInfo") {
			FroniusSymJSON_GetLoggerLEDInfo_Parse($hash, $data);
		} else {
			FroniusSymJSON_Log($hash, 1, "Error. Unknown call for ".$param->{call}); 
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
		 FroniusSymJSON_InitAttr($own_hash);
	}
}

sub FroniusSymJSON_InitAttr($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};

	FroniusSymJSON_Log $hash, 1, "Initialising user setting (attr) for $name";
	
	if ($init_done) {
		if (defined $attr{$name}{unit_day}) {
			$unit_day = $attr{$name}{unit_day};
		} else {
			$unit_day = "Wh";
			FroniusSymJSON_Log $hash, 5, "attr unit_day not set, using default";
		}
		if (defined $attr{$name}{unit_current}) {
			$unit_current = $attr{$name}{unit_current};
		} else {
			$unit_current = "W";
			FroniusSymJSON_Log $hash, 5, "attr unit_current not set, using default";
		}
		if (defined $attr{$name}{unit_total}) {
			$unit_total = $attr{$name}{unit_total};
		} else {
			$unit_total = "Wh";
			FroniusSymJSON_Log $hash, 5, "attr unit_total not set, using default";
		}
		if (defined $attr{$name}{unit_year}) {
			$unit_year =  $attr{$name}{unit_year};
		} else {
			$unit_year =  "Wh";
			FroniusSymJSON_Log $hash, 5, "attr unit_year not set, using default";
		}
		if (defined $attr{$name}{Request_CommonInverterData}) {
			$request_CommonInverterData = $attr{$name}{Request_CommonInverterData};
		}
		if (defined $attr{$name}{Request_LoggerLEDInfo}) {
			$request_LoggerLEDInfo = $attr{$name}{Request_LoggerLEDInfo};
		}
		if (defined $attr{$name}{Request_MinMaxInverterData}) {
			$request_MinMaxInverterData = $attr{$name}{Request_MinMaxInverterData};
		}
		if (defined $attr{$name}{Request_SystemCumulationInverterData}) {
			$request_SystemCumulationInverterData = $attr{$name}{Request_SystemCumulationInverterData};
		}
		
		FroniusSymJSON_Log $hash, 5, "User setting (attr) initialised for $name";
	} else {
		FroniusSymJSON_Log $hash, 1, "Fhem not ready yet, retry in 5 seconds";
	  	InternalTimer(gettimeofday() + 5, "FroniusSymJSON_InitAttr", $hash, 0);
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
