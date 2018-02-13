local squadAttack = {}

-- imports

local constants = require("Constants")
local mapUtils = require("MapUtils")
local unitGroupUtils = require("UnitGroupUtils")
local playerUtils = require("PlayerUtils")
local movementUtils = require("MovementUtils")
local mathUtils = require("MathUtils")
local chunkPropertyUtils = require("ChunkPropertyUtils")

-- constants

local PLAYER_PHEROMONE = constants.PLAYER_PHEROMONE
local MOVEMENT_PHEROMONE = constants.MOVEMENT_PHEROMONE
local BASE_PHEROMONE = constants.BASE_PHEROMONE
local RESOURCE_PHEROMONE = constants.RESOURCE_PHEROMONE

local SQUAD_RAIDING = constants.SQUAD_RAIDING
local SQUAD_SETTLING = constants.SQUAD_SETTLING
local SQUAD_GUARDING = constants.SQUAD_GUARDING

local PLAYER_PHEROMONE_MULTIPLER = constants.PLAYER_PHEROMONE_MULTIPLER

local DEFINES_GROUP_FINISHED = defines.group_state.finished
local DEFINES_GROUP_GATHERING = defines.group_state.gathering
local DEFINES_GROUP_MOVING = defines.group_state.moving
local DEFINES_GROUP_ATTACKING_DISTRACTION = defines.group_state.attacking_distraction
local DEFINES_GROUP_ATTACKING_TARGET = defines.group_state.attacking_target
local DEFINES_DISTRACTION_BY_ENEMY = defines.distraction.by_enemy
local DEFINES_DISTRACTION_BY_ANYTHING = defines.distraction.by_anything

local SENTINEL_IMPASSABLE_CHUNK = constants.SENTINEL_IMPASSABLE_CHUNK

-- imported functions

local mRandom = math.random

local findMovementPosition = movementUtils.findMovementPosition

local getNeighborChunks = mapUtils.getNeighborChunks
local addSquadToChunk = chunkPropertyUtils.addSquadToChunk
local getChunkByXY = mapUtils.getChunkByXY
local positionToChunkXY = mapUtils.positionToChunkXY
local addMovementPenalty = movementUtils.addMovementPenalty
local lookupMovementPenalty = movementUtils.lookupMovementPenalty
local calculateKamikazeThreshold = unitGroupUtils.calculateKamikazeThreshold
local positionFromDirectionAndChunk = mapUtils.positionFromDirectionAndChunk

local euclideanDistanceNamed = mathUtils.euclideanDistanceNamed

local playersWithinProximityToPosition = playerUtils.playersWithinProximityToPosition
local getPlayerBaseGenerator = chunkPropertyUtils.getPlayerBaseGenerator

local scoreNeighborsForAttack = movementUtils.scoreNeighborsForAttack
local scoreNeighborsForResource = movementUtils.scoreNeighborsForResource

-- module code

local function scoreResourceLocation(squad, neighborChunk)
    local settle = (2*neighborChunk[MOVEMENT_PHEROMONE]) + neighborChunk[RESOURCE_PHEROMONE]
    return settle - lookupMovementPenalty(squad, neighborChunk)
end

local function scoreAttackLocation(squad, neighborChunk)
    local damage = (2*neighborChunk[MOVEMENT_PHEROMONE]) + neighborChunk[BASE_PHEROMONE] + (neighborChunk[PLAYER_PHEROMONE] * PLAYER_PHEROMONE_MULTIPLER)
    return damage - lookupMovementPenalty(squad, neighborChunk)
end

local function settleMove(map, attackPosition, attackCmd, squad, group, natives, surface)
    local groupState = group.state
    
    if (groupState == DEFINES_GROUP_FINISHED) or (groupState == DEFINES_GROUP_GATHERING) or ((groupState == DEFINES_GROUP_MOVING) and (squad.cycles == 0)) then
	local groupPosition = group.position
	local x, y = positionToChunkXY(groupPosition)
	local chunk = getChunkByXY(map, x, y)
	local attackChunk, attackDirection = scoreNeighborsForAttack(chunk,
								       getNeighborChunks(map, x, y),
								       scoreResourceLocation,
								       squad)
	if (chunk ~= SENTINEL_IMPASSABLE_CHUNK) then
	    addSquadToChunk(map, chunk, squad)
	    addMovementPenalty(natives, squad, chunk)
	elseif (attackChunk ~= SENTINEL_IMPASSABLE_CHUNK) then
	    addSquadToChunk(map, attackChunk, squad)
	    addMovementPenalty(natives, squad, attackChunk)
	end
	if group.valid and (attackChunk ~= SENTINEL_IMPASSABLE_CHUNK) then
	    local resourceGenerator = getResourceGenerator(map, attackChunk)
	    -- or max distance is hit
	    if (resourceGenerator == 0) or ((groupState == DEFINES_GROUP_FINISHED) or (groupState == DEFINES_GROUP_GATHERING)) then
		
		squad.cycles = ((#squad.group.members > 80) and 6) or 4

		attackCmd.distraction = DEFINES_DISTRACTION_BY_ENEMY

		local position = findMovementPosition(surface, positionFromDirectionAndChunk(attackDirection, groupPosition, attackPosition, 1.35))
		if position then
		    attackPosition.x = position.x
		    attackPosition.y = position.y

		    group.set_command(attackCmd)
		    group.start_moving()
		else
		    addMovementPenalty(natives, squad, attackChunk)
		end
	    elseif (resourceGenerator ~= 0) then
		-- settle chunk
	    end
	end
    end
end


local function attackMove(map, attackPosition, attackCmd, squad, group, natives, surface)
    local groupState = group.state
    
    if (groupState == DEFINES_GROUP_FINISHED) or (groupState == DEFINES_GROUP_GATHERING) or ((groupState == DEFINES_GROUP_MOVING) and (squad.cycles == 0)) then
	local groupPosition = group.position
	local x, y = positionToChunkXY(groupPosition)
	local chunk = getChunkByXY(map, x, y)
	local attackChunk, attackDirection = scoreNeighborsForAttack(chunk,
								     getNeighborChunks(map, x, y),
								     scoreAttackLocation,
								     squad)
	if (chunk ~= SENTINEL_IMPASSABLE_CHUNK) then
	    addSquadToChunk(map, chunk, squad)
	    addMovementPenalty(natives, squad, chunk)
	elseif (attackChunk ~= SENTINEL_IMPASSABLE_CHUNK) then
	    addSquadToChunk(map, attackChunk, squad)
	    addMovementPenalty(natives, squad, attackChunk)
	end
	if group.valid and (attackChunk ~= SENTINEL_IMPASSABLE_CHUNK) then
	    local playerBaseGenerator = getPlayerBaseGenerator(map, attackChunk)
	    if (playerBaseGenerator == 0) or ((groupState == DEFINES_GROUP_FINISHED) or (groupState == DEFINES_GROUP_GATHERING)) then
		
		squad.cycles = ((#squad.group.members > 80) and 6) or 4

		local moreFrenzy = not squad.rabid and squad.frenzy and (euclideanDistanceNamed(groupPosition, squad.frenzyPosition) < 100)
		squad.frenzy = moreFrenzy
		
		if squad.rabid or squad.frenzy then
		    attackCmd.distraction = DEFINES_DISTRACTION_BY_ANYTHING
		else
		    attackCmd.distraction = DEFINES_DISTRACTION_BY_ENEMY
		end

		local position = findMovementPosition(surface, positionFromDirectionAndChunk(attackDirection, groupPosition, attackPosition, 1.35))
		if position then
		    attackPosition.x = position.x
		    attackPosition.y = position.y

		    group.set_command(attackCmd)
		    group.start_moving()
		else
		    addMovementPenalty(natives, squad, attackChunk)
		end
	    elseif not squad.frenzy and not squad.rabid and
		((groupState == DEFINES_GROUP_ATTACKING_DISTRACTION) or (groupState == DEFINES_GROUP_ATTACKING_TARGET) or
		    (playerBaseGenerator ~= 0)) then
		    squad.frenzy = true
		    squad.frenzyPosition.x = groupPosition.x
		    squad.frenzyPosition.y = groupPosition.y
	    end
	end
    end
end

function squadAttack.squadsDispatch(map, surface, natives)
    local squads = natives.squads
    local attackPosition = map.position
    local attackCmd = map.attackAreaCommand
    local settleCmd = map.settleCommand

    for i=1,#squads do
        local squad = squads[i]
        local group = squad.group
        if group and group.valid then

	    if (squad.status == SQUAD_RAIDING) then
		attackMove(map, attackPosition, attackCmd, squad, group, natives, surface)
	    elseif (squad.status == SQUAD_SETTLING) then
		settleMove(map, attackPosition, settleCmd, squad, group, natives, surface)
	    end
        end
    end
end

function squadAttack.squadsBeginAttack(natives, players)
    local squads = natives.squads
    for i=1,#squads do
        local squad = squads[i]
	local group = squad.group
        if not squad.settlers and (squad.status == SQUAD_GUARDING) and group and group.valid then
	    local kamikazeThreshold = calculateKamikazeThreshold(#squad.group.members, natives)

	    local groupPosition = group.position	    
	    if playersWithinProximityToPosition(players, groupPosition, 100) then
		squad.frenzy = true
		squad.frenzyPosition.x = groupPosition.x
		squad.frenzyPosition.y = groupPosition.y
	    end
	    
	    squad.kamikaze = mRandom() < kamikazeThreshold
	    squad.status = SQUAD_RAIDING
	end
    end
end

return squadAttack
