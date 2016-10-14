------------------------------------------------------------------------
--- @file arp.lua
--- @brief Address resolution protocol (ARP) utility.
--- Utility functions for the arp_header struct
--- defined in \ref headers.lua . \n
--- Includes:
--- - Arp constants
--- - Arp address utility
--- - Arp header utility
--- - Definition of Arp packets
--- - Arp handler task
------------------------------------------------------------------------

local ffi = require "ffi"
local pkt = require "packet"

require "headers"
local dpdkc = require "dpdkc"
local dpdk = require "dpdk"
local memory = require "memory"
local filter = require "filter"
local ns = require "namespaces"
local libmoon = require "libmoon"
local pipe = require "pipe"
local log = require "log"

local eth = require "proto.ethernet"

local ntoh, hton = ntoh, hton
local ntoh16, hton16 = ntoh16, hton16
local bor, band, bnot, rshift, lshift= bit.bor, bit.band, bit.bnot, bit.rshift, bit.lshift
local format = string.format
local istype = ffi.istype


--------------------------------------------------------------------------------------------------------
---- ARP constants (c.f. http://www.iana.org/assignments/arp-parameters/arp-parameters.xhtml)
--------------------------------------------------------------------------------------------------------

--- Arp protocol constants
local arp = {}

--- Hardware address type for ethernet
arp.HARDWARE_ADDRESS_TYPE_ETHERNET = 1

--- Proto address type for IP (for ethernet based protocols uses etherType numbers \ref ethernet.lua)
arp.PROTO_ADDRESS_TYPE_IP = 0x0800

--- Operation: request
arp.OP_REQUEST = 1
--- Operation: reply
arp.OP_REPLY = 2


--------------------------------------------------------------------------------------------------------
---- ARP header
--------------------------------------------------------------------------------------------------------

--- Module for arp_header struct (see \ref headers.lua).
local arpHeader = {}
arpHeader.__index = arpHeader

--- Set the hardware address type.
--- @param int Type as 16 bit integer.
function arpHeader:setHardwareAddressType(int)
	int = int or arp.HARDWARE_ADDRESS_TYPE_ETHERNET
	self.hrd = hton16(int)
end

--- Retrieve the hardware address type.
--- @return Type as 16 bit integer.
function arpHeader:getHardwareAddressType()
	return hton16(self.hrd)
end

--- Retrieve the hardware address type.
--- @return Type in string format.
function arpHeader:getHardwareAddressTypeString()
	local type = self:getHardwareAddressType()
	if type == arp.HARDWARE_ADDRESS_TYPE_ETHERNET then
		return "Ethernet"
	else
		return format("0x%04x", type)
	end
end
	
--- Set the protocol address type.
--- @param int Type as 16 bit integer.
function arpHeader:setProtoAddressType(int)
	int = int or arp.PROTO_ADDRESS_TYPE_IP
	self.pro = hton16(int)
end

--- Retrieve the protocol address type.
--- @return Type as 16 bit integer.
function arpHeader:getProtoAddressType()
	return hton16(self.pro)
end

--- Retrieve the protocol address type.
--- @return Type in string format.
function arpHeader:getProtoAddressTypeString()
	local type = self:getProtoAddressType()
	if type == arp.PROTO_ADDR_TYPE_IP then
		return "IPv4"
	else
		return format("0x%04x", type)
	end
end

--- Set the hardware address length.
--- @param int Length as 8 bit integer.
function arpHeader:setHardwareAddressLength(int)
	int = int or 6
	self.hln = int
end

--- Retrieve the hardware address length.
--- @return Length as 8 bit integer.
function arpHeader:getHardwareAddressLength()
	return self.hln
end

--- Retrieve the hardware address length.
--- @return Length in string format.
function arpHeader:getHardwareAddressLengthString()
	return self:getHardwareAddressLength()
end

--- Set the protocol address length.
--- @param int Length as 8 bit integer.
function arpHeader:setProtoAddressLength(int)
	int = int or 4
	self.pln = int
end

--- Retrieve the protocol address length.
--- @return Length as 8 bit integer.
function arpHeader:getProtoAddressLength()
	return self.pln
end

--- Retrieve the protocol address length.
--- @return Length in string format.
function arpHeader:getProtoAddressLengthString()
	return self:getProtoAddressLength()
end

--- Set the operation.
--- @param int Operation as 16 bit integer.
function arpHeader:setOperation(int)
	int = int or arp.OP_REQUEST
	self.op = hton16(int)
end

--- Retrieve the operation.
--- @return Operation as 16 bit integer.
function arpHeader:getOperation()
	return hton16(self.op)
end

--- Retrieve the operation.
--- @return Operation in string format.
function arpHeader:getOperationString()
	local op = self:getOperation()
	if op == arp.OP_REQUEST then
		return "Request"
	elseif op == arp.OP_REPLY then
		return "Reply"
	else
		return op
	end
end

--- Set the hardware source address.
--- @param addr Address in 'union mac_address' format.
function arpHeader:setHardwareSrc(addr)
	self.sha:set(addr)
end

--- Retrieve the hardware source address.
--- @return Address in 'union mac_address' format.
function arpHeader:getHardwareSrc()
	return self.sha:get()
end

--- Set the hardware source address.
--- @param addr Address in string format.
function arpHeader:setHardwareSrcString(addr)
	self.sha:setString(addr)
end

--- Retrieve the hardware source address.
--- @return Address in string format.
function arpHeader:getHardwareSrcString()
	return self.sha:getString()
end

--- Set the hardware destination address.
--- @param addr Address in 'union mac_address' format.
function arpHeader:setHardwareDst(addr)
	self.tha:set(addr)
end

--- Retrieve the hardware destination address.
--- @return Address in 'union mac_address' format.
function arpHeader:getHardwareDst()
	return self.tha:get()
end

--- Set the hardware destination address.
--- @param addr Address in string format.
function arpHeader:setHardwareDstString(addr)
	self.tha:setString(addr)
end

--- Retrieve the hardware destination address.
--- @return Address in string format.
function arpHeader:getHardwareDstString()
	return self.tha:getString()
end

--- Set the protocol source address.
--- @param addr Address in 'struct ip4_address' format.
function arpHeader:setProtoSrc(addr)
	self.spa:set(addr)
end

--- Retrieve the protocol source address.
--- @return Address in 'struct ip4_address' format.
function arpHeader:getProtoSrc()
	return self.spa:get()
end

--- Set the protocol source address.
--- @param addr Address in source format.
function arpHeader:setProtoSrcString(addr)
	self.spa:setString(addr)
end

--- Retrieve the protocol source address.
--- @return Address in string format.
function arpHeader:getProtoSrcString()
	return self.spa:getString()
end

--- Set the protocol destination address.
--- @param addr Address in 'struct ip4_address' format.
function arpHeader:setProtoDst(addr)
	self.tpa:set(addr)
end

--- Retrieve the protocol destination address.
--- @return Address in 'struct ip4_address' format.
function arpHeader:getProtoDst()
	return self.tpa:get()
end

--- Set the protocol destination address.
--- @param addr Address in string format.
function arpHeader:setProtoDstString(addr)
	self.tpa:setString(addr)
end

--- Retrieve the protocol destination address.
--- @return Address in string format.
function arpHeader:getProtoDstString()
	return self.tpa:getString()
end

--- Set all members of the ip header.
--- Per default, all members are set to default values specified in the respective set function.
--- Optional named arguments can be used to set a member to a user-provided value.
--- @param args Table of named arguments. Available arguments: HardwareAddressType, ProtoAddressType, HardwareAddressLength, ProtoAddressLength, Operation, HardwareSrc, HardwareDst, ProtoSrc, ProtoDst
--- @param pre prefix for namedArgs. Default 'arp'.
--- @code
--- fill() --- only default values
--- fill{ arpOperation=2, ipTTL=100 } --- all members are set to default values with the exception of arpOperation
--- @endcode
function arpHeader:fill(args, pre)
	args = args or {}
	pre = pre or "arp"
	
	self:setHardwareAddressType(args[pre .. "HardwareAddressType"])
	self:setProtoAddressType(args[pre .. "ProtoAddressType"])
	self:setHardwareAddressLength(args[pre .. "HardwareAddressLength"])
	self:setProtoAddressLength(args[pre .. "ProtoAddressLength"])
	self:setOperation(args[pre .. "Operation"])

	local hwSrc = pre .. "HardwareSrc"
	local hwDst = pre .. "HardwareDst"
	local prSrc = pre .. "ProtoSrc"
	local prDst = pre .. "ProtoDst"
	args[hwSrc] = args[hwSrc] or "01:02:03:04:05:06"
	args[hwDst] = args[hwDst] or "07:08:09:0a:0b:0c"
	args[prSrc] = args[prSrc] or "0.1.2.3"
	args[prDst] = args[prDst] or "4.5.6.7"
	
	-- if for some reason the address is in 'union mac_address'/'union ipv4_address' format, cope with it
	if type(args[hwSrc]) == "string" then
		self:setHardwareSrcString(args[hwSrc])
	else
		self:setHardwareSrc(args[hwSrc])
	end
	if type(args[hwDst]) == "string" then
		self:setHardwareDstString(args[hwDst])
	else
		self:setHardwareDst(args[hwDst])
	end
	
	if type(args[prSrc]) == "string" then
		self:setProtoSrcString(args[prSrc])
	else
		self:setProtoSrc(args[prSrc])
	end
	if type(args[prDst]) == "string" then
		self:setProtoDstString(args[prDst])
	else
		self:setProtoDst(args[prDst])
	end
end

--- Retrieve the values of all members.
--- @param pre prefix for namedArgs. Default 'arp'.
--- @return Table of named arguments. For a list of arguments see "See also".
--- @see arpHeader:fill
function arpHeader:get(pre)
	pre = pre or "arp"

	local args = {}
	args[pre .. "HardwareAddressType"] = self:getHardwareAddressType()
	args[pre .. "ProtoAddressType"] = self:getProtoAddressType()
	args[pre .. "HardwareAddressLength"] = self:getHardwareAddressLength()
	args[pre .. "ProtoAddressLength"] = self:getProtoAddressLength()
	args[pre .. "Operation"] = self:getOperation()
	args[pre .. "HardwareSrc"] = self:getHardwareSrc()
	args[pre .. "HardwareDst"] = self:getHardwareDst()
	args[pre .. "ProtoSrc"] = self:getProtoSrc()
	args[pre .. "ProtoDst"] = self:getProtoDst() 

	return args
end

--- Retrieve the values of all members.
--- @return Values in string format.
function arpHeader:getString()
	local str = "ARP hrd " 			.. self:getHardwareAddressTypeString() 
				.. " (hln " 		.. self:getHardwareAddressLengthString() 
				.. ") pro " 		.. self:getProtoAddressTypeString() 
				.. " (pln " 		.. self:getProtoAddressLength(String) 
				.. ") op " 			.. self:getOperationString()

	local op = self:getOperation()
	if op == arp.OP_REQUEST then
		str = str .. " who-has " 	.. self:getProtoDstString() 
				  .. " (" 			.. self:getHardwareDstString() 
				  .. ") tell " 		.. self:getProtoSrcString() 
				  .. " (" 			.. self:getHardwareSrcString() 
				  .. ")"
	elseif op == arp.OP_REPLY then
		str = str .. " " 			.. self:getProtoSrcString() 
				  .. " is-at " 		.. self:getHardwareSrcString() 
				  .. " (for " 		.. self:getProtoDstString() 
				  .. " @ " 			.. self:getHardwareDstString() 
				  .. ")"
	else
		str = str .. " " 			.. self:getHardwareSrcString() 
				  .. " > " 			.. self:getHardwareDstString() 
				  .. " " 			.. self:getProtoSrcString() 
				  .. " > " 			.. self:getProtoDstString()
	end

	return str
end

--- Resolve which header comes after this one (in a packet).
--- For instance: in tcp/udp based on the ports.
--- This function must exist and is only used when get/dump is executed on
--- an unknown (mbuf not yet casted to e.g. tcpv6 packet) packet (mbuf)
--- @return String next header (e.g. 'udp', 'icmp', nil)
function arpHeader:resolveNextHeader()
	return nil
end

--- Change the default values for namedArguments (for fill/get).
--- This can be used to for instance calculate a length value based on the total packet length.
--- See proto/ip4.setDefaultNamedArgs as an example.
--- This function must exist and is only used by packet.fill.
--- @param pre The prefix used for the namedArgs, e.g. 'arp'
--- @param namedArgs Table of named arguments (see See Also)
--- @param nextHeader The header following after this header in a packet
--- @param accumulatedLength The so far accumulated length for previous headers in a packet
--- @return Table of namedArgs
--- @see arpHeader:fill
function arpHeader:setDefaultNamedArgs(pre, namedArgs, nextHeader, accumulatedLength)
	return namedArgs
end
	
---------------------------------------------------------------------------------
---- Packets
---------------------------------------------------------------------------------

--- Cast the packet to an Arp packet 
pkt.getArpPacket = packetCreate("eth", "arp")


---------------------------------------------------------------------------------
---- ARP Handler Task
---------------------------------------------------------------------------------

--- ARP table timeout in seconds
local ARP_AGING_TIME = 30

--- Arp handler task, responds to ARP queries for given IPs and performs arp lookups
--- @todo TODO implement garbage collection/refreshing entries \n
--- the current implementation does not handle large tables efficiently \n
arp.arpTask = "__MG_ARP_TASK"

--- Start the ARP task on a shared core
--- @param queues array of queue pairs to use, each entry has the following format
--- {rxQueue = rxQueue, txQueue = txQueue, ips = "ip" | {"ip", ...}}
--- rxQueue is optional, packets can alternatively be provided through the pipe API, see arp.handlePacket()
function arp.startArpTask(queues)
	libmoon.startSharedTask(arp.arpTask, queues)
end

-- Arp table
local arpTable = ns:get()
local pipes = ns:get()

local function handleArpPacket(rxBufs, txBufs, nic, ipToMac)
	local rxPkt = rxBufs[1]:getArpPacket()
	if rxPkt.eth:getType() == eth.TYPE_ARP then
		if rxPkt.arp:getOperation() == arp.OP_REQUEST then
			local ip = rxPkt.arp:getProtoDst()
			local mac = ipToMac[ip]
			if mac then
				txBufs:alloc(60)
				-- TODO: a single-packet API would be nice for things like this
				local pkt = txBufs[1]:getArpPacket()
				pkt.eth:setSrcString(mac)
				pkt.eth:setDst(rxPkt.eth:getSrc())
				pkt.arp:setOperation(arp.OP_REPLY)
				pkt.arp:setHardwareDst(rxPkt.arp:getHardwareSrc())
				pkt.arp:setHardwareSrcString(mac)
				pkt.arp:setProtoDst(rxPkt.arp:getProtoSrc())
				pkt.arp:setProtoSrc(ip)
				nic.txQueue:send(txBufs)
			end
		elseif rxPkt.arp:getOperation() == arp.OP_REPLY then
			-- learn from all arp replies we see (yes, that makes arp cache poisoning easy)
			local mac = rxPkt.arp:getHardwareSrcString()
			local ip = rxPkt.arp:getProtoSrcString()
			arpTable[tostring(parseIPAddress(ip))] = {
				state = "current",
				mac = mac,
				timestamp = time(),
				updateTime = time()
			}
		end
	end
	rxBufs:freeAll()
end

local function arpTask(qs)
	-- two ways to call this: single nic or array of nics
	if qs[1] == nil and qs.txQueue then
		return arpTask({ qs })
	end

	local ipToMac = {}
	-- loop over NICs/Queues
	for i, nic in ipairs(qs) do
		if nic.rxQueue and nic.txQueue.id ~= nic.rxQueue.id then
			error("both queues must belong to the same device")
		end

		if type(nic.ips) == "string" then
			nic.ips = { nic.ips }
		end
		for _, ip in pairs(nic.ips) do
			ipToMac[parseIPAddress(ip)] = nic.txQueue.dev:getMacString()
		end
		if nic.rxQueue then
			nic.txQueue.dev:l2Filter(eth.TYPE_ARP, nic.rxQueue)
		end
		local pipe = pipe:newFastPipe()
		nic.pipe = pipe
		pipes[tostring(i)] = pipe
	end

	local rxBufs = memory.createBufArray(1)
	local txMem = memory.createMemPool(function(buf)
		buf:getArpPacket():fill{ 
			arpOperation	= arp.OP_REPLY,
			pktLength		= 60
		}
	end)
	local txBufs = txMem:bufArray(1)
	
	arpTable.taskRunning = true

	while libmoon.running() do
		
		for _, nic in pairs(qs) do
			if nic.rxQueue then
				rx = nic.rxQueue:tryRecvIdle(rxBufs, 1000)
				assert(rx <= 1)
				if rx > 0 then
					handleArpPacket(rxBufs, txBufs, nic, ipToMac)
				end
			end
			local pkt = nic.pipe:tryRecv(100)
			if pkt then
				rxBufs[1] = pkt
				handleArpPacket(rxBufs, txBufs, nic, ipToMac)
			end
		end

		local timedOutEntries = {}
		-- send requests 
		arpTable:forEach(function(ip, value)
			local ts = time()
			if type(value) ~= "table" then
				return
			end
			-- current and updated less than ARP_AGING_TIME ago
			if value.state == "current" and value.timestamp + ARP_AGING_TIME > ts  then
				return
			end
			-- requested less than a second ago
			if (value.state == "requested" or value.state == "refreshing") and value.timestamp + 1 > ts then
				return
			end
			-- didn't get a response while refreshing
			if value.state == "refreshing" and value.lookupTime + ARP_AGING_TIME < ts  then
				table.insert(timedOutEntries, ip)
				return
			end
			-- didn't get a reponse, ever
			if value.state == "requested" and value.lookupTime + ARP_AGING_TIME < ts  then
				table.insert(timedOutEntries, ip)
				return
			end
			if value.state == "current" then
				value.state = "refreshing"
				value.lookupTime = ts
			end
			if value.state  == "pending" then
				value.state = "requested"
				value.lookupTime = ts
			end
			value.timestamp = ts
			arpTable[ip] = value
			ip = tonumber(ip)
			txBufs:alloc(60)
			local pkt = txBufs[1]:getArpPacket()
			pkt.eth:setDstString(eth.BROADCAST)
			pkt.arp:setOperation(arp.OP_REQUEST)
			pkt.arp:setHardwareDstString(eth.BROADCAST)
			pkt.arp:setProtoDst(ip)
			-- TODO: do not send requests on all devices, but only the relevant
			for _, nic in pairs(qs) do
				local mac = nic.txQueue.dev:getMacString()
				pkt.eth:setSrcString(mac)
				pkt.arp:setProtoSrc(parseIPAddress(nic.ips[1]))
				pkt.arp:setHardwareSrcString(mac)
				nic.txQueue:send(txBufs)
			end
		end)
		for _, ip in ipairs(timedOutEntries) do
			arpTable[ip] = nil
		end
		libmoon.sleepMillisIdle(1)
	end
end

--- Send a buf containing an ARP packet to the ARP task.
--- The buf is free'd by the ARP task, do not free this (or increase ref count if you still need the buf).
--- @param buf the arp packet
--- @param nic the ID of the NIC from which the packt was received, defaults to 1
---            corresponds to the index in the queue array passed to the arp task
function arp.handlePacket(buf, nic)
	nic = nic or 1
	local pipe = pipes[tostring(nic)]
	if not pipe then
		log:fatal("NIC %s not found", nic)
	end
	pipe:send(buf)
end

--- Perform a non-blocking lookup in the ARP table.
--- Lookup the MAC address for a given IP.
--- Blocks for up to 1 second if the arp task is not yet running
--- Caution: this function uses locks and namespaces, must not be used in the fast path
--- @param ip The ip address in string or cdata format to look up.
function arp.lookup(ip)
	if type(ip) == "string" then
		ip = parseIPAddress(ip)
	elseif type(ip) == "cdata" then
		ip = ip:get()
	end
	if not arpTable.taskRunning then
		local waitForArpTask = 0
		while not arpTable.taskRunning and waitForArpTask < 10 do
			libmoon.sleepMillis(100)
		end
		if not arpTable.taskRunning then
			error("ARP task is not running")
		end
	end
	local mac = arpTable[tostring(ip)]
	if type(mac) == "table" then
		return mac.mac, mac.updateTime
	end
	arpTable.lock(function()
		if not arpTable[tostring(ip)] then
			arpTable[tostring(ip)] = {state = "pending", timestamp = time()}
		end
	end)
	return nil
end

--- Perform a blocking lookup in the ARP table.
--- @param ip The ip address in string or cdata format to look up.
--- @param timeout timeout in seconds
function arp.blockingLookup(ip, timeout)
	local timeout = libmoon.getTime() + timeout
	repeat
		local mac, ts = arp.lookup(ip)
		if mac then
			return mac, ts
		end
		libmoon.sleepMillisIdle(1000)
	until libmoon.getTime() >= timeout or not libmoon.running()
end

function arp.waitForStartup()
	while not arpTable.taskRunning and libmoon.running() do
		libmoon.sleepMillisIdle(1)
	end
end

__MG_ARP_TASK = arpTask


---------------------------------------------------------------------------------
---- Metatypes
---------------------------------------------------------------------------------

ffi.metatype("struct arp_header", arpHeader)

return arp

