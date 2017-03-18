--
-- AIDriveStrategyCollisionOtherAI
--  drive strategy to stop vehicle on collision (aiTrafficCollision trigger)
--
-- Copyright (C) GIANTS Software GmbH, Confidential, All Rights Reserved.

AIDriveStrategyCollisionOtherAI = {}
local AIDriveStrategyCollisionOtherAI_mt = Class(AIDriveStrategyCollisionOtherAI, AIDriveStrategy)

function AIDriveStrategyCollisionOtherAI:new(customMt)
	if customMt == nil then
		customMt = AIDriveStrategyCollisionOtherAI_mt
	end

	local self = AIDriveStrategy:new(customMt)
	
	self.collisionTime = 0
	
	return self
end

function AIDriveStrategyCollisionOtherAI:delete()
	AIDriveStrategyCollisionOtherAI:superClass().delete(self)

	if self.vehicle.isServer then
		for triggerID,list in pairs(self.collidingVehicles) do
			removeTrigger(triggerID)
		end
		self.collidingVehicles = {}
	end
end

function AIDriveStrategyCollisionOtherAI:setAIVehicle(vehicle)
	AIDriveStrategyCollisionOtherAI:superClass().setAIVehicle(self, vehicle)

	if self.vehicle.isServer then
		self.collidingVehicles = {}
		if self.vehicle.acOtherCombineCollisionTriggerR ~= nil then
			local triggerID = self.vehicle.acOtherCombineCollisionTriggerR
			self.collidingVehicles[triggerID] = {}
			addTrigger( triggerID, "onOtherAICollisionTrigger", self )
		end
		if self.vehicle.acOtherCombineCollisionTriggerL ~= nil then
			local triggerID = self.vehicle.acOtherCombineCollisionTriggerL
			self.collidingVehicles[triggerID] = {}
			addTrigger( triggerID, "onOtherAICollisionTrigger", self )
		end
		self.start = true
	end
end

function AIDriveStrategyCollisionOtherAI:getDriveData(dt, vX,vY,vZ)
	-- we do not check collisions at the back, at least currently
	self.vehicle.aiveMaxCollisionSpeed = nil
	self.vehicle.aiveCollisionDistance = nil
	self.start = nil
	
	if self.vehicle.movingDirection < 0 and self.vehicle:getLastSpeed(true) > 2 then
		return nil, nil, nil, nil, nil
	end
	
	local triggerId 
	if     self.vehicle.acParameters == nil 
			or self.vehicle.acParameters.upNDown then
	elseif self.vehicle.acParameters.rightAreaActive then
		triggerId = self.vehicle.acOtherCombineCollisionTriggerR
	else
		triggerId = self.vehicle.acOtherCombineCollisionTriggerL
	end

	if triggerId ~= nil then
		for otherAI,bool in pairs(self.collidingVehicles[triggerId]) do
			if bool and otherAI.aiIsStarted then
				local blocked = true
				
				if      g_currentMission.time < self.collisionTime + 2000 then
				
					local tX,_,tZ = localToWorld(self.vehicle.aiVehicleDirectionNode, 0,0,1)
					table.insert(self.vehicle.debugTexts, " AIDriveStrategyCollisionOtherAI :: STOP due to collision ")
					return tX, tZ, true, 0, math.huge
					
				elseif  otherAI.aiVehicleDirectionNode ~= nil 
						and otherAI.aiveIsStarted 
						and otherAI.acLastWantedSpeed ~= nil
						and otherAI.acTurnStage       <= 0 
						and otherAI.acLastWantedSpeed  > 6 then
					local angle   = AutoSteeringEngine.getRelativeYRotation( otherAI.aiVehicleDirectionNode, self.vehicle.aiVehicleDirectionNode )
					if math.abs( angle ) < 0.1667 * math.pi then
						blocked = false 
						local s = otherAI.motor.speedLimit * math.cos( angle )
						if     self.vehicle.aiveMaxCollisionSpeed == nil
								or self.vehicle.aiveMaxCollisionSpeed  > s then
							self.vehicle.aiveMaxCollisionSpeed = s
						end
						local wx1, _, wz1 = getWorldTranslation( otherAI.aiVehicleDirectionNode )
						local wx2, _, wz2 = getWorldTranslation( self.vehicle.aiVehicleDirectionNode )
						local d = Utils.vector2Length( wx1-wx2, wz1-wz2 )
						if     self.vehicle.aiveCollisionDistance == nil
								or self.vehicle.aiveCollisionDistance  > d then
							self.vehicle.aiveCollisionDistance = d
						end
					end
				end
				
				if blocked then
					local tX,_,tZ = localToWorld(self.vehicle.aiVehicleDirectionNode, 0,0,1)
					table.insert(self.vehicle.debugTexts, " AIDriveStrategyCollisionOtherAI :: STOP due to collision ")
					
					self.collisionTime = g_currentMission.time 

					if not self.stopNotificationShown then
						self.stopNotificationShown = true
						g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, string.format(g_i18n:getText(AIVehicle.REASON_TEXT_MAPPING[AIVehicle.STOP_REASON_BLOCKED_BY_OBJECT]), self.vehicle.currentHelper.name))
						self.vehicle:setBeaconLightsVisibility(true, false)
					end

					return tX, tZ, true, 0, math.huge
				end
			end
		end
	end

	if self.stopNotificationShown then
		self.stopNotificationShown = false
		self.vehicle:setBeaconLightsVisibility(false, false)
	end

	table.insert(self.vehicle.debugTexts, " AIDriveStrategyCollisionOtherAI :: no collision ")
	return nil, nil, nil, nil, nil
end

function AIDriveStrategyCollisionOtherAI:updateDriving(dt)
end

function AIDriveStrategyCollisionOtherAI:onOtherAICollisionTrigger(triggerId, otherId, onEnter, onLeave, onStay, otherShapeId)
--print(" HIT @:"..self.vehicle.configFileName.."   IN   "..getName(triggerId).."   BY   "..getName(otherId)..", "..getName(otherShapeId))

	if g_currentMission.players[otherId] == nil then
		local vehicle = g_currentMission.nodeToVehicle[otherId]
		local otherAI = nil
			
		if vehicle ~= nil then
			if vehicle.specializations ~= nil and SpecializationUtil.hasSpecialization( AIVehicle, vehicle.specializations ) then
				otherAI = vehicle 
			elseif type( vehicle.getRootAttacherVehicle ) == "function" then
				otherAI = vehicle:getRootAttacherVehicle()
				if not SpecializationUtil.hasSpecialization( AIVehicle, otherAI.specializations ) then
					otherAI = nil
				end
			end
		end
			
		if      otherAI ~= nil
				and otherAI ~= self.vehicle then
			if onLeave then
				self.collidingVehicles[triggerId][otherAI] = nil
			else
				self.collidingVehicles[triggerId][otherAI] = true
			end
		end		
	end
end

