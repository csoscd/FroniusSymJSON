# FroniusSymJSON
FHEM Module for accessing the Fronius API via http/JSON

##Attributes

### avoidDailyBug
Possible values: 0|1

In some firmware versions there seems to be a bug in the DAY_ENERGY value. The counting for the yearly value and for the total value
seems to be correct. Therefore if avoidDailyBug is set to 1 the following will happen:
At the first connection to the Inverter during the day (which usually should be somewhere after midnight) the current value of yearly value
will be stored in a reading YEAR_SUM_TODAY_START. Everytime now the energy info is pulled from the Inverter:

day value = current yearly value - YEAR_SUM_TODAY_START

will be calculated. Additionally, the value read from the inverter will be stored in a reading ENERGY_DAY_READ_SUM. This allows you to
compare the calculated and the inverter value.

### device_ids
Possible values: colon seperated list of device IDs

Example:

attr Wechselrichter device_ids 1:2

According to my information device IDs are just counted (0 1 2).

### interval
Possible values: Integer

Time in seconds between two pull requests to the Inverter.

### interval_night
Possible values: Integer

Time in seconds between two pull requests to the Inverter during the night. The FHEM function is_day() is used to check. If the attribute is not
set, the same time will be used 24hours a day.

### listdevices
Possible values: 0|1

If set to 1 all devices will have their own readings. Otherwise only the total values will be stored.

### unit_current
Possible values: W|kW|MW|GW


### unit_day
Possible values: Wh|kWh|MWh|GWh

### unit_total
Possible values: Wh|kWh|MWh|GWh

### unit_year
Possible values: Wh|kWh|MWh|GWh
