# FroniusSymJSON
FHEM Module for accessing the Fronius API via http/JSON

# Attributes

## avoidDailyBug
Possible values: 0|1

In some firmware versions there seems to be a bug in the DAY_ENERGY value. The counting for the yearly value and for the total value
seems to be correct. Therefore if avoidDailyBug is set to 1 the following will happen:
At the first connection to the Inverter during the day (which usually should be somewhere after midnight) the current value of yearly value
will be stored in a reading YEAR_SUM_TODAY_START. Everytime now the energy info is pulled from the Inverter, the day value = current yearly value - YEAR_SUM_TODAY_START.