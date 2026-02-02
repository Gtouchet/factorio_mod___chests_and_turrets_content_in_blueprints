-----------------------------------
-- Configuration: list of supported entities
-- Chests and turrets whose inventory can be saved/restored
-----------------------------------
local accepted_chests = {
	["wooden-chest"] = true,
	["iron-chest"] = true,
	["steel-chest"] = true,
	["active-provider-chest"] = true,
	["passive-provider-chest"] = true,
	["storage-chest"] = true,
	["buffer-chest"] = true,
	["requester-chest"] = true,
}

local accepted_turrets = {
	["gun-turret"] = true,
}



-----------------------------------
-- Turret handling
-- Save and restore turret ammo inventory using blueprint tags
-----------------------------------
function snapshot_turrets_content(blueprint, mapping)
	local blueprint_entities = blueprint.get_blueprint_entities()
	if not blueprint_entities then return end

	for i, blueprint_entity in ipairs(blueprint_entities) do
		if accepted_turrets[blueprint_entity.name] then
			local source = mapping[blueprint_entity.entity_number]
			if source and source.valid then
				local inventory = source.get_inventory(defines.inventory.turret_ammo)
				if inventory and inventory.valid then
					local tags = {}
					for slot = 1, #inventory do
						local stack = inventory[slot]
						if stack and stack.valid_for_read then
							tags[#tags + 1] = {
								entity_type = blueprint_entity.name,
								name = stack.name,
								count = stack.count,
								quality = stack.quality,
							}
						end
					end
					blueprint.set_blueprint_entity_tags(i, {
						tags = tags,
					})
				end
			end
		end
	end
end

function apply_turret_inventory(player, turret, ghost)
	local turret_inventory = turret.get_inventory(defines.inventory.turret_ammo)
	if not turret_inventory and turret_inventory.valid then return end
	
	if not ghost.tags then return end
	
	for _, item in pairs(ghost.tags) do
		local player_item_count = player_item_count(player, item)
		if player_item_count < item.count then
			item.count = player_item_count
		end
		if item.count > 0 then
			remove_from_player_inventory(player, item)
			turret_inventory.insert({
				name = item.name,
				count = item.count,
				quality = item.quality,
			})
		end
	end
end



-----------------------------------
-- Chest handling
-- Save and restore chest inventories, preserving item stacks and slot positions
-----------------------------------
function snapshot_chests_content(blueprint, mapping)
	local blueprint_entities = blueprint.get_blueprint_entities()
	if not blueprint_entities then return end

	for i, blueprint_entity in ipairs(blueprint_entities) do
		if accepted_chests[blueprint_entity.name] then
			local source = mapping[blueprint_entity.entity_number]
			if source and source.valid then
				local inventory = source.get_inventory(defines.inventory.chest)
				if inventory and inventory.valid then
					local tags = {}
					for slot = 1, #inventory do
						local stack = inventory[slot]
						if stack and stack.valid_for_read then
							tags[#tags + 1] = {
								entity_type = blueprint_entity.name,
								name = stack.name,
								count = stack.count,
								slot = slot,
								quality = stack.quality,
							}
						end
					end
					blueprint.set_blueprint_entity_tags(i, {
						tags = tags,
					})
				end
			end
		end
	end
end

function apply_chest_inventory(player, chest, ghost)
	local chest_inventory = chest.get_inventory(defines.inventory.chest)
	if not chest_inventory and chest_inventory.valid then return end
	
	if not ghost.tags then return end

	for _, item in pairs(ghost.tags) do
		local player_item_count = player_item_count(player, item)
		if player_item_count < item.count then
			item.count = player_item_count
		end
		if item.count > 0 then
			remove_from_player_inventory(player, item)
			chest_inventory[item.slot].set_stack({
				name = item.name,
				count = item.count,
				quality = item.quality,
			})
		end
	end
end



-----------------------------------
-- Player inventory handling
-----------------------------------
function player_item_count(player, item)
	if not player and player.valid then return 0 end
	return player.get_main_inventory().get_item_count({
		name = item.name,
		quality = item.quality,
	})
end

function remove_from_player_inventory(player, item)
	if not player and player.valid then return 0 end
	return player.get_main_inventory().remove({
		name = item.name,
		count = item.count,
		quality = item.quality,
	})
end



-----------------------------------
-- Ghost cache
-- Stores entity-ghost tags by position until the real entity is built
-----------------------------------
local ghosts = {}

function save_ghost_tags(entity)
	local tags = entity.tags
	if tags then
		ghosts[entity.position.x .. "," .. entity.position.y] = tags
	end
end

function remove_ghost(position)
	if ghosts[position] then
		ghosts[position] = nil
	end
end



-----------------------------------
-- Autobuild mod compatibility
-----------------------------------
local autobuild_mod_enabled = false

script.on_load(function()
	autobuild_mod_enabled = script.active_mods["autobuild"] ~= nil
end)

function handle_autobuild_built_entity(event)
	local player = game.get_player(event.player_index)
	if not player then return end

	local entity = event.entity
	if not entity or not entity.valid then return end

	save_ghost_tags(entity)
	local position = entity.position.x .. "," .. entity.position.y
	local pre_existing_ghost = ghosts[position]

	if not pre_existing_ghost or not pre_existing_ghost.tags or not pre_existing_ghost.tags[1] then
		return
	end
	
	local entity_type = pre_existing_ghost.tags[1].entity_type

	local can_build_entity = player_item_count(player, {
		name = entity_type,
		count = 1,
	}) > 0
	if not can_build_entity then
		return
	end
	
	if accepted_turrets[entity_type] then
		local turret = game.surfaces[entity.surface.name].create_entity{
			name = entity_type,
			position = entity.position,
			force = game.forces.player,
		}
		apply_turret_inventory(player, turret, pre_existing_ghost)
		remove_from_player_inventory(player, {
			name = entity_type,
			count = 1,
		})
	end

	if accepted_chests[entity_type] then
		local chest = game.surfaces[entity.surface.name].create_entity{
			name = entity_type,
			position = entity.position,
			force = game.forces.player,
		}
		apply_chest_inventory(player, chest, pre_existing_ghost)
		remove_from_player_inventory(player, {
			name = entity_type,
			count = 1,
		})
	end

	remove_ghost(position)
end



-----------------------------------
-- API events
-----------------------------------
script.on_event(defines.events.on_player_setup_blueprint, function(event)
	local blueprint = event.stack
	if not blueprint and blueprint.valid then return end
	
	local mapping = event.mapping.get()
	if not mapping then return end
	
	snapshot_turrets_content(blueprint, mapping)
	snapshot_chests_content(blueprint, mapping)
end)

script.on_event(defines.events.on_built_entity, function(event)
	if autobuild_mod_enabled then
		handle_autobuild_built_entity(event)
		return
	end

	local player = game.get_player(event.player_index)
	if not player then return end
	
	local entity = event.entity
	if not entity or not entity.valid then return end
	
	if entity.name == "entity-ghost" then
		save_ghost_tags(entity)
	else
		local position = entity.position.x .. "," .. entity.position.y
		local pre_existing_ghost = ghosts[position]
		if pre_existing_ghost then
			if accepted_turrets[entity.name] then
				apply_turret_inventory(player, entity, pre_existing_ghost)
			end
			if accepted_chests[entity.name] then
				apply_chest_inventory(player, entity, pre_existing_ghost)
			end
			remove_ghost(position)
		end
	end
end)

script.on_event(defines.events.on_player_mined_entity, function(event)
	local entity = event.entity
	if not entity or not entity.valid then return end
	
	if not entity.name == "entity-ghost" then return end

	remove_ghost(entity.position.x .. "," .. entity.position.y)
end)

script.on_event(defines.events.on_pre_ghost_deconstructed, function(event)
	local ghost = event.ghost
	if not ghost and ghost.valid then return end

	remove_ghost(ghost.position.x .. "," .. ghost.position.y)
end)

