module("L_Arduino", package.seeall)

--
-- MySensors Gateway Plugin
-- 
-- Created by Henrik Ekblad <henrik.ekblad@mysensors.org>
--
-- http://www.mysensors.org
-- https://github.com/mysensors
--
-- See github for contributors
-- Ethernet contribution by A-lurker
--	
-- This program is free software; you can redistribute it and/or
-- modify it under the terms of the GNU General Public License
-- version 2 as published by the Free Software Foundation.
--

-- number of times to retry each message
local MyRetries = 10
-- seconds to wait until next check
local MyWait = 1

local MyPrefix = "****<-*->**** " -- only used for logging clarity
local MyMsgs = {}
local MyMsgsRetries = {}
local nowChecking = false
local processingMsg = false
local bufferActive = false

local PLUGIN_NAME = "MySensors Gateway Plugin"
local PLUGIN_VERSION = "1.4"
local GATEWAY_VERSION = ""
local IP_PORT = "5003"
local BAUD_RATE = "115200"
local ARDUINO_SID = "urn:upnp-arduino-cc:serviceId:arduino1"
local VARIABLE_CONTAINER_SID = "urn:upnp-org:serviceId:VContainer1"
local MAX_RADIO_ID=255
local NODE_CHILD_ID="255"

local ARDUINO_DEVICE
local TASK_ERROR = 2
local TASK_ERROR_PERM = -2
local TASK_SUCCESS = 4
local TASK_BUSY = 1
local childIdLookupTable = {}
local availableIds = {}
local inclusionResult = {}
local includeCount = 0

local msgType = { 
	PRESENTATION = "0",  
	SET 		 = "1", 
	REQUEST 	 = "2", 
	INTERNAL 	 = "3", 
	STREAM 	 	 = "4"
}

local tDeviceLookupNumType = {}
local tDeviceTypes = {
	DOOR = 		  {0,  "urn:schemas-micasaverde-com:device:DoorSensor:1", "D_DoorSensor1.xml", "Door "},
	MOTION = 	  {1,  "urn:schemas-micasaverde-com:device:MotionSensor:1", "D_MotionSensor1.xml", "Motion "},
	SMOKE = 	  {2,  "urn:schemas-micasaverde-com:device:SmokeSensor:1", "D_SmokeSensor1.xml", "Smoke "},
	LIGHT = 	  {3,  "urn:schemas-upnp-org:device:BinaryLight:1", "D_BinaryLight1.xml", "Light "},
	DIMMER = 	  {4,  "urn:schemas-upnp-org:device:DimmableLight:1", "D_DimmableLight1.xml", "Dim Light "},
	COVER = 	  {5,  "urn:schemas-micasaverde-com:device:WindowCovering:1", "D_WindowCovering1.xml", "Win Covering " },
	TEMP = 		  {6,  "urn:schemas-micasaverde-com:device:TemperatureSensor:1", "D_TemperatureSensor1.xml", "Temp "},
	HUM = 		  {7,  "urn:schemas-micasaverde-com:device:HumiditySensor:1", "D_HumiditySensor1.xml", "Humidity "},
	BARO = 		  {8,  "urn:schemas-micasaverde-com:device:BarometerSensor:1", "D_BarometerSensor1.xml", "Baro "},
	WIND = 		  {9,  "urn:schemas-micasaverde-com:device:WindSensor:1", "D_WindSensor1.xml", "Wind "},
	RAIN = 		  {10, "urn:schemas-micasaverde-com:device:RainSensor:1", "D_RainSensor1.xml", "Rain "},
	UV = 		    {11, "urn:schemas-micasaverde-com:device:UvSensor:1", "D_UvSensor1.xml", "UV "},
	WEIGHT = 	  {12, "urn:schemas-micasaverde-com:device:ScaleSensor:1", "D_ScaleSensor1.xml", "Weight "},
	POWER = 	  {13, "urn:schemas-micasaverde-com:device:PowerMeter:1", "D_PowerMeter1.xml", "Power "},
	HEATER = 	  {14, "urn:schemas-upnp-org:device:Heater:1", "D_Heater1.xml", "Heater "},
	DISTANCE = 	  {15, "urn:schemas-upnp-org:device:Distance:1", "D_DistanceSensor1.xml", "Distance "},
	LIGHT_LEVEL=  {16, "urn:schemas-micasaverde-com:device:LightSensor:1", "D_LightSensor1.xml", "Light "},
	ARDUINO_NODE= {17, "urn:schemas-arduino-cc:device:arduinonode:1", "D_ArduinoNode1.xml", "Node "},
	ARDUINO_RELAY={18, "urn:schemas-arduino-cc:device:arduinorelay:1", "D_ArduinoRelay1.xml", "Repeater "},
	LOCK = 		    {19, "urn:micasaverde-com:serviceId:DoorLock1", "D_DoorLock1.xml", "Lock "},
	IR = 		      {20, "urn:schemas-arduino-cc:device:ArduinoIr:1", "D_ArduinoIr1.xml", "IR "}, 
	WATER = 	    {21, "urn:schemas-micasaverde-com:device:WaterMeter:1", "D_WaterMeter1.xml", "Water "},
	AIR_QUALITY = {22, "urn:schemas-micasaverde-com:device:AirQuality:1", "D_AirQuality1.xml", "Air Quality "}, -- device files missing
  CUSTOM =      {23, "urn:schemas-micasaverde-com:device:GenericSensor:1", "D_GenericSensor1.xml", "Generic "}, 
  DUST =        {24, "urn:schemas-micasaverde-com:device:Dust:1", "D_DustSensor1.xml", "Dust "},  -- device files missing
  SCENE_CONTROLLER = {25, "urn:schemas-micasaverde-com:device:SceneController:1", "D_SceneController1.xml", "SceneCtrl "}

}

local tVarLookupNumType = {}
local tVarTypes = {
	TEMP = 			{0,  "urn:upnp-org:serviceId:TemperatureSensor1", "CurrentTemperature", ""},
	HUM = 			{1,  "urn:micasaverde-com:serviceId:HumiditySensor1", "CurrentLevel", "" },
	LIGHT = 		{2,  "urn:upnp-org:serviceId:SwitchPower1", "Status", "0" },
	DIMMER = 		{3,  "urn:upnp-org:serviceId:Dimming1", "LoadLevelStatus", "" },
	PRESSURE = 		{4,  "urn:upnp-org:serviceId:BarometerSensor1", "CurrentPressure", "" },
	FORECAST = 		{5,  "urn:upnp-org:serviceId:BarometerSensor1", "Forecast", "" },
	RAIN = 			{6,  "urn:upnp-org:serviceId:RainSensor1", "CurrentTRain", "" },
	RAINRATE = 		{7,  "urn:upnp-org:serviceId:RainSensor1", "CurrentRain", "" },
	WIND = 			{8,  "urn:upnp-org:serviceId:WindSensor1", "AvgSpeed", "" },
	GUST = 			{9,  "urn:upnp-org:serviceId:WindSensor1", "GustSpeed", "" },
	DIRECTION = 	{10, "urn:upnp-org:serviceId:WindSensor1", "Direction", "" },
	UV = 			{11, "urn:upnp-org:serviceId:UvSensor1", "CurrentLevel", "" },
	WEIGHT = 		{12, "urn:micasaverde-com:serviceId:ScaleSensor1", "Weight", "" },
	DISTANCE = 		{13, "urn:micasaverde-com:serviceId:DistanceSensor1", "CurrentDistance", "" },
	IMPEDANCE = 	{14, "urn:micasaverde-com:serviceId:ScaleSensor1", "Impedance", "" },
	ARMED = 		{15, "urn:micasaverde-com:serviceId:SecuritySensor1", "Armed", "" },
	TRIPPED = 		{16, "urn:micasaverde-com:serviceId:SecuritySensor1", "Tripped", "0" },
	WATT = 			{17, "urn:micasaverde-com:serviceId:EnergyMetering1", "Watts", "" },
	KWH = 			{18, "urn:micasaverde-com:serviceId:EnergyMetering1", "KWH", "0" },
	SCENE_ON = 		{19, "urn:micasaverde-com:serviceId:SceneController1", "sl_SceneActivated", "" },
	SCENE_OFF = 	{20, "urn:micasaverde-com:serviceId:SceneController1", "sl_SceneDeactivated", "" },
	HEATER = 		{21, "urn:upnp-org:serviceId:TemperatureSetpoint1_Heat", "CurrentSetpoint", "" },
	HEATER_SW = 	{22, "urn:upnp-org:serviceId:HVAC_UserOperatingMode1", "ModeStatus", "" },
	LIGHT_LEVEL = 	{23, "urn:micasaverde-com:serviceId:LightSensor1", "CurrentLevel", "" },
	VAR_1 = 		{24, "urn:upnp-org:serviceId:VContainer1", "Variable1", ""},
	VAR_2 = 		{25, "urn:upnp-org:serviceId:VContainer1", "Variable2", ""},
	VAR_3 = 		{26, "urn:upnp-org:serviceId:VContainer1", "Variable3", ""},
	VAR_4 = 		{27, "urn:upnp-org:serviceId:VContainer1", "Variable4", ""},
	VAR_5 = 		{28, "urn:upnp-org:serviceId:VContainer1", "Variable5", ""},
	UP = 		    {29, nil, nil, ""},
	DOWN = 		    {30, nil, nil, ""},
	STOP = 			{31, nil, nil, ""},
	IR_SEND =		{32, nil, nil, ""},
	IR_RECEIVE = 	{33, "urn:upnp-org:serviceId:ArduinoIr1", "IrCode", ""},
	FLOW = 			{34, "urn:micasaverde-com:serviceId:WaterMetering1", "Flow", "" },
	VOLUME = 		{35, "urn:micasaverde-com:serviceId:WaterMetering1", "Volume", "0" },
	LOCK = 		    {36, "urn:micasaverde-com:serviceId:DoorLock1", "Status", ""},
	DUST_LEVEL =  {37, "urn:micasaverde-com:serviceId:DustSensor1", "DustLevel", ""},
  VOLTAGE =  {38, "urn:micasaverde-com:serviceId:EnergyMetering1", "Voltage", ""},
  CURRENT =  {39, "urn:micasaverde-com:serviceId:EnergyMetering1", "Current", ""}
}

local tVeraTypes = {
	BATTERY_DATE = 	{0, "urn:micasaverde-com:serviceId:HaDevice1", "BatteryDate", "" },
	LAST_TRIP = 	{1, "urn:micasaverde-com:serviceId:SecuritySensor1", "LastTrip", "" },
  LAST_UPDATE = 	{2, "urn:micasaverde-com:serviceId:HaDevice1", "LastUpdate", "" }
}

local tInternalLookupNumType = {}
local tInternalTypes = {
	BATTERY_LEVEL = {0, "urn:micasaverde-com:serviceId:HaDevice1", "BatteryLevel", "" },
	TIME = 			{1, nil, nil, nil},
 	VERSION = 		{2, "urn:upnp-arduino-cc:serviceId:arduinonode1", "ArduinoLibVersion", ""},
 	ID_REQUEST = 	{3, nil, nil, nil},
 	ID_RESPONSE = 	{4, nil, nil, nil},
 	INCLUSION_MODE ={5, "urn:upnp-arduino-cc:serviceId:arduino1", "InclusionMode", "0"},
  CONFIG =        {6, "urn:upnp-arduino-cc:serviceId:arduinonode1", "RelayNode", ""},
  PING = 			{7, nil, nil, nil },
  PING_ACK =      {8, nil, nil, nil },
  LOG_MESSAGE =   {9, nil, nil, nil },
  CHILDREN =  	{10, "urn:upnp-arduino-cc:serviceId:arduinonode1", "Children", "0"},
  SKETCH_NAME    = {11, "urn:upnp-arduino-cc:serviceId:arduinonode1", "SketchName", ""},
	SKETCH_VERSION = {12, "urn:upnp-arduino-cc:serviceId:arduinonode1", "SketchVersion", ""},
	REBOOT         = {13, nil, nil, nil}, 
	GATEWAY_READY  = {14, nil, nil, nil}
}


local function printTable(list, i)
    local listString = ''
    if not i then
        listString = listString .. '{'
    end
    i = i or 1
    local element = list[i]
    if not element then
        return listString .. '}'
    end
    if(type(element) == 'table') then
        listString = listString .. printTable(element)
    else
        listString = listString .. element
    end
    return listString .. ', ' .. printTable(list, i + 1)
end



local function log(text, level)
	if(type(text) == 'table') then
		luup.log("Arduino: table:" .. printTable(text) , (level or 50))
    elseif (text == nil) then
		luup.log("Arduino: nil-value" , (level or 50))
	else    
		luup.log(MyPrefix .. "Arduino: " .. text, (level or 50))
	end
end

--
-- Update variable if changed
-- Return true if changed or false if no change
--
function setVariableIfChanged(serviceId, name, value, deviceId)
    log(MyPrefix .. serviceId ..","..name..", "..value..", ".. deviceId)
    local curValue = luup.variable_get(serviceId, name, deviceId)
    
    if ((value ~= curValue) or (curValue == nil) or (serviceId == "urn:micasaverde-com:serviceId:SceneController1")) then
        luup.variable_set(serviceId, name, value, deviceId)
        return true
        
    else
        return false
        
    end
end


local function setLastUpdate(nodeDevice)
	if (nodeDevice ~= nil) then
		local timestamp = os.time()
		local variable = tVeraTypes["LAST_UPDATE"]
		setVariableIfChanged(variable[2], variable[3], timestamp, nodeDevice)
	
		-- Set the last update in a human readable form for display on the console
		local unit = luup.variable_get(ARDUINO_SID, "Unit", ARDUINO_DEVICE)
		local timeFormat = (unit == 'M' and '%H:%M' or '%I:%M %p')			
		setVariableIfChanged(variable[2], "LastUpdateHR", os.date(timeFormat, timestamp), nodeDevice)
	else

		log("Unable to update LAST_UPDATE due to missing parent node.", 2)
	end 
end

local function setVariable(incomingData, childId, nodeId)
	if (childId ~= nil) then
		-- Set variable on child sensor.
		local index = tonumber(incomingData[5]);
		local varType = tVarLookupNumType[index]
		local var = tVarTypes[varType]
		local value = incomingData[6]
		local timestamp = os.time()
		if (var[2] ~= nil) then 
			log("Setting variable '".. var[3] .. "' to value '".. value.. "'")
			setVariableIfChanged(var[2], var[3], value, childId)
		
			-- Handle special variables battery level and tripped which also
			-- should update other variables to os.time()
			if (varType == "TRIPPED" and value == "1") then
				local variable = tVeraTypes["LAST_TRIP"]
				setVariableIfChanged(variable[2], variable[3], timestamp, childId)
			else
				local variable = tVeraTypes["LAST_UPDATE"]
				setVariableIfChanged(variable[2], variable[3], timestamp, childId)
			end
		end

		-- Always update LAST_UPDATE for node	
		if (nodeId ~= nil) then
			local nodeDevice = childIdLookupTable[nodeId .. ";" .. NODE_CHILD_ID] 
			setLastUpdate(nodeDevice)
		end
	end
end

local function task(text, mode)
	if (mode == TASK_ERROR_PERM) then
		log(text, 1)
	elseif (mode ~= TASK_SUCCESS) then
		log(text, 2)
	else
		log(text)
	end
	if (mode == TASK_ERROR_PERM) then
		taskHandle = luup.task(text, TASK_ERROR, "MySensors plugin", taskHandle)
	else
		taskHandle = luup.task(text, mode, "MySensors plugin", taskHandle)

		-- Clear the previous error, since they're all transient
		if (mode ~= TASK_SUCCESS) then
			luup.call_delay("clearTask", 15, "", false)
		end
	end
end

local function clearTask()
	task("Clearing...", TASK_SUCCESS)
end
 
local function nextAvailiableRadioId()
	for i=1,255 do 
		if (availableIds[i] == true) then
			availableIds[i] = false
			return i
		end
	end
	return 255
end
 
-- Function to send a message to sensor
function sendCommand(altid, variableId, value)
	return sendCommandWithMessageType(altid, "SET", 1, tonumber(tVarTypes[variableId][1]), value)
end

function sendNodeCommand(device, variableId, value)
	return sendCommandWithMessageType(luup.devices[device].id, "SET", 1, tonumber(tVarTypes[variableId][1]), value)
end

function sendInternalCommand(altid, variableId, value)
	return sendCommandWithMessageType(altid, "INTERNAL",0, tonumber(tInternalTypes[variableId][1]), value)
end

function sendRequestResponse(altid, variableId, value)
	return sendCommandWithMessageType(altid, "SET", 0, tonumber(tVarTypes[variableId][1]), value)
end


local function presentation(incomingData, device, childId, altId)
	local type = incomingData[5]
	local data = incomingData[6]
	local mode = luup.variable_get(ARDUINO_SID, "InclusionMode", ARDUINO_DEVICE)

	if (mode == "1" and device == nil) then
		-- A new sensor (not created before) was presented during inclusion mode
		if (inclusionResult[altId] == nil) then 
			log("Found new device "..altId);
			includeCount = includeCount+1;
			setVariableIfChanged(ARDUINO_SID, "InclusionFoundCountHR", includeCount .." devices found", ARDUINO_DEVICE)
			inclusionResult[altId] = type
		end
	elseif (mode == "0" and device ~= nil and childId == NODE_CHILD_ID) then
		-- Store version information if this is radio node
		local var = tInternalTypes["VERSION"]
		setVariableIfChanged(var[2], var[3], data, device)
		if (data ~= GATEWAY_VERSION) then
			-- The library version of sensor differs from plugin version. Warn about it.
			log("Warning: Sensor has different library version than GW. Id: "..altId)
		end
	end
end 

local function processInternalMessage(incomingData, iChildId, iAltId, incomingNodeId)
	local data = incomingData[6]
	local index = tonumber(incomingData[5]);
	local varType = tInternalLookupNumType[index]
	local var = tInternalTypes[varType]

	if (varType == "VERSION" and iAltId == "0;0") then
		-- Store version of Arduino Gateway
		GATEWAY_VERSION = data
		setVariableIfChanged(ARDUINO_SID, "ArduinoLibVersion", GATEWAY_VERSION, ARDUINO_DEVICE)
	elseif ((varType == "SKETCH_NAME" or varType == "SKETCH_VERSION") and iChildId ~= nil) then
		-- Store the Sketch name and Version
		setVariableIfChanged(var[2], var[3], data, iChildId)
	elseif (varType == "TIME") then
		-- Request time was sent from one of the sensors
		sendInternalCommand(iAltId,"TIME",os.time() + 3600 * luup.timezone)
	elseif (varType == "ID_REQUEST") then
		-- Determine next available radioid and sent it to the sensor
		sendInternalCommand(iAltId,"ID_RESPONSE",nextAvailiableRadioId())
	elseif (varType == "CONFIG" and iChildId ~= nil) then
		-- Update last update value for this node
		setLastUpdate(iChildId)
		-- Update parent node information
		setVariableIfChanged(var[2], var[3], data, iChildId)
		-- Create a human readable form for parent
		setVariableIfChanged(var[2], "RelayNodeHR", data == "0" and "GW" or data, iChildId)
		-- Send back configuration to node
		local unit = luup.variable_get(ARDUINO_SID, "Unit", ARDUINO_DEVICE)
		sendInternalCommand(iAltId,"CONFIG",unit)
	elseif (varType == "BATTERY_LEVEL") then
		setVariableIfChanged(var[2], var[3], data, iChildId)
		local variable = tVeraTypes["BATTERY_DATE"]
		setVariableIfChanged(variable[2], variable[3], os.time(), iChildId)
	elseif (varType == "INCLUSION_MODE") then
		setVariableIfChanged(var[2], var[3], data, ARDUINO_DEVICE)
		if (data == "0") then
			setVariableIfChanged(ARDUINO_SID, "InclusionFoundCountHR", "", ARDUINO_DEVICE)
			inclusionCount = 0
			-- Here comes the presentation data from sensors
			local newDevices = 0
			local child_devices
			log("Inclusion mode ended.")
			for altId,deviceType in pairs(inclusionResult) do
				local childId = childIdLookupTable[altId] 
				if (childId == nil) then 
					local deviceId = tDeviceLookupNumType[tonumber(deviceType)]
					if (deviceId ~= nil) then		
						local splitted = altId:split(";")
						local nodeId = splitted[1]
						local childId = splitted[2]
						local name

						-- A new child sensor has been found. Create it!
						local deviceType = tDeviceTypes[deviceId]
						-- Create device if device sent presentation
						if (newDevices == 0) then
							child_devices = luup.chdev.start(ARDUINO_DEVICE)
						end

						if (childId == NODE_CHILD_ID) then
							name = nodeId
						else
							name = nodeId .. ":" .. childId
						end

						-- append newly found sensor device
						luup.chdev.append(ARDUINO_DEVICE, child_devices, altId, "Arduino " .. deviceType[4]..name, deviceType[2],deviceType[3],"","",false)
						newDevices = newDevices + 1		
					else 
						log("Found unknown device type ".. deviceType ..". Inclusion aborted. Please try again.", 1)
						newDevices = -100
					end
				else 
					log("Device "..altId.." already exists");
				end
			end
			if (newDevices > 0) then
				-- Append all old device children
				for k, v in pairs(luup.devices) do
					if v.device_num_parent == ARDUINO_DEVICE then
						luup.chdev.append(ARDUINO_DEVICE, child_devices, v.id, v.description, v.device_type,v.device_file,"","",false)
					end
				end
				task ("Found new sensor(s). Need to restart. Please wait.",TASK_BUSY)
				luup.chdev.sync(ARDUINO_DEVICE,child_devices)
				return
			end
		else
			setVariableIfChanged(ARDUINO_SID, "InclusionFoundCountHR", "0 devices found", ARDUINO_DEVICE)
		end	
	elseif (varType == "CHILDREN") then
		setVariableIfChanged(var[2], var[3], data, iChildId)
	elseif (varType == "LOG_MESSAGE" or varType == "GATEWAY_READY") then
		log(MyPrefix .. "Log MSG: "..data)
	else
		log(MyPrefix .. "Incoming internal command '" .. table.concat(incomingData, ";") .. "' discarded for child: " .. (iChildId ~= nil and iChildId or "nil"), 2)
	end
end

local function requestStatus(incomingData, childId, altId)
	log("Requesting status for: "..altId)
	-- A device request its current status from vera (when staring up)
	local index = tonumber(incomingData[5]);	
	local varType = tVarLookupNumType[index]
	
	-- Requested variable value from one of the sensors 
	local variable = tVarTypes[varType]
	if (variable[2] ~= nil and childId ~= nil) then 
		local value = luup.variable_get(variable[2], variable[3], childId)
		log("Request status for ".. variable[3])
		if (value ~= nil) then
			-- Send variable value to actuator
			sendRequestResponse(altId,varType,value)
		else
			-- Create the missing variable and send default value to actuator
			setVariableIfChanged(variable[2], variable[3], variable[4], childId)
			sendRequestResponse(altId,varType,variable[4])
		end
	end
	
end

-- ********* START ************* MyFunctions QUEUE ******************************

-- adds cmd msg to the list before sending
function addToMyQueue(myCmd)

	local isFound = inTable(MyMsgs, myCmd)
	-- if not already in the list, add it
	if (isFound == false) then
		table.insert( MyMsgs, myCmd )
		table.insert( MyMsgsRetries, 0)
	end
	
end

-- check if msg is in the list to remove it
function checkMyQueue(msg)
	log(MyPrefix .. ">T> queue        : " .. printTable(MyMsgs) )
	log(MyPrefix .. ">T> queue retries: " .. printTable(MyMsgsRetries) )
	local isFound = inTable(MyMsgs, msg);
	-- if msg found, remove it because has been executed
	if (isFound ~= false) then
		log("msg found in pos: "..isFound..". Removing from list...")
		deleteFromQueue(isFound)
		else
			log("msg not found in list") 
		end
	log(MyPrefix .. ">T> queue updated: " .. printTable(MyMsgs) )
	log(MyPrefix .. ">T> queue retries: " .. printTable(MyMsgsRetries) )
end

-- check if item exists in queue
function inTable(tbl, item)
    for key, value in pairs(tbl) do
        if value == item then return key end
    end
    return false
end

-- check for lost messages in order to re-send them
local function doCheck()
	log("-=OOOO-CHK-OOOO=- processing: "..tostring(processingMsg)..", cheking: "..tostring(nowChecking))
	if(processingMsg == false)then
		local qLen = table.getn(MyMsgs)
		
		log("-=OOOO-chk-OOOO=-  queue length: ".. qLen)
		log("-=OOOO-chk-OOOO=-  queue        : " .. printTable(MyMsgs) )
		if(qLen >0) then

			local msg=MyMsgs[qLen]
			local retr=MyMsgsRetries[qLen]

		    log("queue last elem: ".. msg.. " retried: "..retr)

		    -- if more tries than specified, just delete it and give up
		    if(retr >= MyRetries)then
		    	deleteFromQueue(qLen)
		    	log(MyPrefix .. "-=OOOO-del-OOOO=-  too many retries")
		    	log(MyPrefix .. "-=OOOO-del-OOOO=-  queue        : " .. printTable(MyMsgs) )
		    	else
		    		-- if not, update count and resend msg
		    		MyMsgsRetries[qLen] = retr+1
		    		log(MyPrefix .. "-=OOOO-snd-OOOO=- resending: "..msg)
		    		doSendCommand(msg)
		    	end

			if(qLen == 0 ) then
				-- check back in a while
				log("-=OOOO-snd-OOOO=- set cheking off queue just emptied")
				nowChecking=false
				else 
					startMyTimer()
				end
		else
			nowChecking=false
			log("-=OOOO-snd-OOOO=- set cheking off queue <= 0")
		end
	else
		if(nowChecking==false)then
		log("-=OOOO-chk-OOOO=- MSG is being received. Wait for next time")
		startMyTimer()
		end
	end
	
end


--deletes element from queue
function deleteFromQueue(pos)
	table.remove(MyMsgs, pos) 
	table.remove(MyMsgsRetries, pos)
end

-- actual function that sends commands
function doSendCommand(cmd)
log("-=OOOO-snd-OOOO=- processing: "..tostring(processingMsg)..", cheking: "..tostring(nowChecking))
   log("*** **** **** **** *** *** Sending: " .. cmd )
	if (luup.io.write(cmd) == false)  then
		task("Cannot send command - communications error", TASK_ERROR)
		luup.set_failure(true)
		return false
	end
	-- check in a while if message is sent correctly (ack), check if already checking
	if (nowChecking == false) then
		startMyTimer()
	end
	return true
end

-- starts the timer to check
function startMyTimer()
	log("-=OOOO-ooo-OOOO=- starting timer ")
	luup.call_timer("doCheck", 1, MyWait, "", "")
	nowChecking=true
end
-- ****** END **************** MyFunctions QUEUE******************************


function sendCommandWithMessageType(altid, messageType, ack, variableId, value)
	local cmd = altid..";".. msgType[messageType] .. ";" .. ack .. ";" .. variableId .. ";" .. value
	log("Sending: " .. cmd)
	-- only add if SET request
	if (messageType =="SET" and ack==1) then
		addToMyQueue(cmd)
 	end

 	-- this replaces the old send function, now done in doSendCommand()
 	return doSendCommand(cmd)

	--if (luup.io.write(cmd) == false)  then
	--	task("Cannot send command - communications error", TASK_ERROR)
	--	luup.set_failure(true)
	--	return false
	--end
	-- return true
end


function setUnit(unit)
	setVariableIfChanged(ARDUINO_SID, "Unit", unit, ARDUINO_DEVICE)
end


-- Arduino GW device commands
function startInclusion(device)
	return sendInternalCommand("0;0","INCLUSION_MODE","1")
end

function stopInclusion(device)
	return sendInternalCommand("0;0","INCLUSION_MODE","0")
end

-- Arduino GW MyBuffer commands
function useBuffer(enable)
	if(enable==1)then
		bufferActive=true
		else
			bufferActive=false
		end
	log("******************** buffer is "..tostring(bufferActive).."   enable: "..tostring(enable) )
end



-- Arduino relay node device commands

function clearChildren(device)
	local variable = tInternalTypes["CHILDREN"]
	setVariableIfChanged(variable[2], variable[3], "Clearing...", device)
	sendInternalCommand(luup.devices[device].id,"CHILDREN","C")
end


-- Window covering commands

function windowCovering(device, action)
  sendCommand(luup.devices[device].id,action,"")
end

-- Power and dimmer commands
function switchPower(device, newTargetValue)
	log(MyPrefix .. ">F> switchPower")
	sendCommand(luup.devices[device].id,"LIGHT",newTargetValue)
end

function sendIrCommand(device, irCodeNumber)
	sendCommand(luup.devices[device].id,"IR_SEND",irCodeNumber)
end


function setDimmerLevel(device, newLoadlevelTarget)
	sendCommand(luup.devices[device].id,"DIMMER",newLoadlevelTarget)
end

function setLockStatus(device, newTargetValue)
	sendCommand(luup.devices[device].id,"LOCK",newTargetValue)
end


-- Heater commands
function SetTheNewTemp(device, NewCurrentSetpoint)
	sendCommand(luup.devices[device].id,"HEATER",NewCurrentSetpoint)
end

function SetModeTarget(device, NewModeTarget)
	sendCommand(luup.devices[device].id,"HEATER_SW",NewModeTarget)
end



-- Security commands
function setArmed(device, newArmedValue)
	setVariableIfChanged(tVarTypes.ARMED[2], tVarTypes.ARMED[3], newArmedValue, device)
end


function updateLookupTables(radioId, childId, deviceId)
 	childIdLookupTable[radioId..";"..childId] = deviceId
 	availableIds[radioId] = false
end

-- splits a string by a pattern
-- returns an array of the pieces
function string:split(delimiter)
	local result = { }
	local from  = 1
	local delim_from, delim_to = string.find( self, delimiter, from  )
	while delim_from do
		table.insert( result, string.sub( self, from , delim_from-1 ) )
		from  = delim_to + 1
		delim_from, delim_to = string.find( self, delimiter, from  )
	end
	table.insert( result, string.sub( self, from  ) )
	return result
end

function processIncoming(s)
	-- disable checking queue while procesing new msg
	processingMsg = true

	log(MyPrefix .. ">F> processIncoming msg: " .. s)
	log("-=OOOO-inc-OOOO=- processing: "..tostring(processingMsg)..", cheking: "..tostring(nowChecking))

	local incomingData = s:split(";")
	if (#incomingData >=4) then
		-- check if msg is in the queue list to remove it
		checkMyQueue(s);

		local nodeId = incomingData[1]
		local childId = incomingData[2]
		local messageType = incomingData[3];

		local altId = nodeId .. ";" .. childId
		local device = childIdLookupTable[altId] 

		if (messageType==msgType.SET) then
			log("Set variable: ".. s)
			setVariable(incomingData, device, nodeId)
		elseif (messageType==msgType.PRESENTATION) then
			log("Presentation: ".. s)
			presentation(incomingData, device, childId, altId)
		elseif (messageType==msgType.REQUEST) then
			log("Request: ".. s)
			requestStatus(incomingData, device, altId)
		elseif (messageType == msgType.INTERNAL) then
			processInternalMessage(incomingData, device, altId, nodeId)
		else
   		 	log("Receive error: No handler for data: "..s, 1)
		end
	end

	-- enable checking once done
	processingMsg = false
end


function startup(lul_device)
	log(MyPrefix .. ">F> startup")
	ARDUINO_DEVICE = lul_device

	setVariableIfChanged(ARDUINO_SID, "PluginVersion", PLUGIN_VERSION, ARDUINO_DEVICE)

 	local ipa = luup.devices[ARDUINO_DEVICE].ip
    
    local ipAddress = string.match(ipa, '^(%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?)')
    local ipPort    = string.match(ipa, ':(%d+)$')
    
    if (ipAddress ~= nil) then
       if (ipPort == nil) then ipPort = IP_PORT end

	   log('Using network connection: IP address is '..ipAddress..':'..ipPort)
       luup.io.open(ARDUINO_DEVICE, ipAddress, ipPort)

    else -- use serial
       log('Trying for a serial connection')

	   local IOdevice = luup.variable_get("urn:micasaverde-com:serviceId:HaDevice1", "IODevice", ARDUINO_DEVICE)
	   if ((luup.io.is_connected(ARDUINO_DEVICE) == false) or (IOdevice == nil)) then
	   	log("Serial port not connected. First choose the serial port and restart the lua engine.", 1)
	   	task("Choose the Serial Port", TASK_ERROR_PERM)
	   	return false
	   end

	   log("Serial port is connected")

	   -- Check serial settings
	   local baud = luup.variable_get("urn:micasaverde-org:serviceId:SerialPort1", "baud", tonumber(IOdevice))
	   if ((baud == nil) or (baud ~= BAUD_RATE)) then
	   	log("Incorrect setup of the serial port. Select ".. BAUD_RATE .." bauds.", 1)
	   	task("Select ".. BAUD_RATE .." bauds for the Serial Port", TASK_ERROR_PERM)
	   	return false
	   end
	   log("Baud is ".. BAUD_RATE)
    end

	for i=1,MAX_RADIO_ID do 
		availableIds[i] = true;
	end

	-- build an lookup table for child device ids (altid -> id)
	for k, v in pairs(luup.devices) do
		-- if I am the parent device
		if v.device_num_parent == ARDUINO_DEVICE then
			childIdLookupTable[v.id] = k
			local split = v.id:split(";")
			local radioId = tonumber(split[1])
			availableIds[radioId] = false;
		end
	end

	-- create lookup table for variables: numeric value -> key
	for k, v in pairs(tVarTypes) do
		tVarLookupNumType[v[1]] = k
	end	

	for k, v in pairs(tInternalTypes) do
		tInternalLookupNumType[v[1]] = k
	end	

	for k, v in pairs(tDeviceTypes) do
		tDeviceLookupNumType[v[1]] = k
	end	


	local variable = tInternalTypes["UNIT"]
	local unit = luup.variable_get(ARDUINO_SID, "Unit", ARDUINO_DEVICE)
	if (unit == nil) then
		-- Set default value for unit to metric system
		setVariableIfChanged(ARDUINO_SID, "Unit", "M", ARDUINO_DEVICE)
	end

	local variable2 = luup.variable_get(ARDUINO_SID, "buffer_active", ARDUINO_DEVICE)
	if (variable2 == 1) then
		bufferActive=true
		else
			bufferActive=false
		end

	log("** START ****************** buffer is "..tostring(bufferActive))

	GATEWAY_VERSION = luup.variable_get(ARDUINO_SID, "ArduinoLibVersion", ARDUINO_DEVICE)

	-- Request version info from Arduino gateway
	sendCommandWithMessageType("0;0","INTERNAL",0,tonumber(tInternalTypes["VERSION"][1]),"Get Version")
	
	--doCheck() queue timer setup
	_G["doCheck"] = doCheck
	-- checking is disabled until a message is sent
	nowChecking=false
end




