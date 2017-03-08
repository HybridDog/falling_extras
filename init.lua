local load_time_start = os.clock()

local sound_count = 0
local function play_node_sound(pos, name, alt, gain_multiplier)
	if sound_count > 50 then
		return	-- fixes error message spam
	end
	local sound = minetest.registered_nodes[name]
	if not sound
	or not sound.sounds then
		return
	end
	sound = sound.sounds.drop or sound.sounds[alt]
	if not sound then
		return
	end
	minetest.sound_play(sound.name, {pos = pos,
		gain = sound.gain * math.abs(gain_multiplier)})
	sound_count = sound_count+1
	if sound_count == 11 then
		minetest.after(0.1, function()
			sound_count = 0
		end)
	end
end

-- This is used to cache the actual movement_gravity
if not minetest.get_gravity then
	local gravity,grav_updating = 10
	function minetest.get_gravity()
		if not grav_updating then
			gravity = tonumber(minetest.setting_get"movement_gravity")
				or gravity
			grav_updating = true
			minetest.after(50, function()
				grav_updating = false
			end)
		end
		return gravity
	end

	-- Override setting functions a bit
	local set_setting = minetest.setting_set
	function minetest.setting_set(name, v, ...)
		if name == "gravity" then
			name = "movement_gravity"
			gravity = tonumber(v) or gravity
		end
		return set_setting(name, v, ...)
	end
	local get_setting = minetest.setting_get
	function minetest.setting_get(name, ...)
		if name == "gravity" then
			name = "movement_gravity"
		end
		return get_setting(name, ...)
	end
end

-- Used to damage players when sth falls onto them
local damage_near_players
local enable_damage = minetest.setting_getbool"enable_damage"
if enable_damage ~= false then
	function damage_near_players(np, fdmg)
		local dmg = math.floor(math.abs(fdmg) + 0.5)
		if dmg < 1 then
			return
		end
		for _,obj in pairs(minetest.get_objects_inside_radius(np, 2)) do
			if obj:is_player() then
				local pos = obj:getpos()
				if math.abs(np.x - pos.x) < 0.45
				and math.abs(np.z - pos.z) < 0.45
				and pos.y < np.y + 0.5
				and pos.y > np.y - 1.4 then
					obj:set_hp(math.max(0, obj:get_hp() - dmg))
				end
			end
		end
	end
else
	function damage_near_players()
	end
end

local falling_entity = minetest.registered_entities["__builtin:falling_node"]
falling_entity.makes_footstep_sound = true
falling_entity.sound_volume = 1
falling_entity.on_step = function(self, dtime)
	-- Set acceleraiton according to gravity
	local gravity = minetest.get_gravity()
	self.object:setacceleration{x=0, y=-gravity, z=0}
	-- Turn to actual sand when collides to ground or just move
	local bcp = self.object:getpos()
	bcp.y = bcp.y - 0.7 * math.sign(gravity) -- Position of bottom center point
	local bcnn = minetest.get_node(bcp).name
	local bcd = minetest.registered_nodes[bcnn]
	if not bcd
	or bcd.walkable
	or (minetest.get_item_group(self.node.name, "float") ~= 0
		and bcd.liquidtype ~= "none"
	) then
		if bcd and bcd.leveled and
				bcnn == self.node.name then
			local addlevel = self.node.level
			if addlevel == nil or addlevel <= 0 then
				addlevel = bcd.leveled
			end
			if minetest.add_node_level(bcp, addlevel) == 0 then
				self.object:remove()
				return
			end
		elseif bcd and bcd.buildable_to and
				(minetest.get_item_group(self.node.name, "float") == 0 or
				bcd.liquidtype == "none") then
			play_node_sound(bcp, bcnn, "dug", self.sound_volume)
			minetest.remove_node(bcp)
			return
		end
		local np = {x=bcp.x, y=bcp.y+math.sign(gravity), z=bcp.z}
		-- Check what's here
		local n2 = minetest.get_node(np)
		-- If it's not air or liquid, remove node and replace it with
		-- it's drops
		if n2.name ~= "air" and (not minetest.registered_nodes[n2.name] or
				minetest.registered_nodes[n2.name].liquidtype == "none") then
			play_node_sound(np, n2.name, "dug", self.sound_volume)
			minetest.remove_node(np)
			if minetest.registered_nodes[n2.name].buildable_to == false then
				if minetest.get_node(np).name == "air" then
					-- Add dropped items
					local drops = minetest.get_node_drops(n2.name, "")
					for _, dropped_item in pairs(drops) do
						minetest.add_item(np, dropped_item)
					end
				else
					-- Sometimes there are not walkable chests or similar
					local drops = minetest.get_node_drops(self.node.name, "")
					for _, dropped_item in pairs(drops) do
						minetest.add_item(np, dropped_item)
					end
					self.object:remove()
					return
				end
			end
			-- Run script hook
			local _, callback
			for _, callback in ipairs(minetest.registered_on_dignodes) do
				callback(np, n2, nil)
			end
		end
		self.object:remove()
		-- fix crashes if node isn't given
		if not self.node.name then
			minetest.log("error", "[falling extras] falling object near "..minetest.pos_to_string(np).." had no node…")
			return
		end
		-- Play sound, set node, remove entity and damage player(s)
		play_node_sound(np, self.node.name, "dug", self.sound_volume)	-- The place sound sounds weird
		minetest.add_node(np, self.node)
		nodeupdate(np)
		damage_near_players(np, self.sound_volume)
		return
	end
	local vely = self.object:getvelocity().y
	if vely == 0 then
		self.object:setpos(vector.round(self.object:getpos()))
	else
		self.sound_volume = vely * 0.1
	end
end

minetest.register_entity(":__builtin:falling_node", falling_entity)


local time = math.floor(tonumber(os.clock()-load_time_start)*100+0.5)/100
local msg = "[falling_extras] loaded after ca. "..time
if time > 0.05 then
	print(msg)
else
	minetest.log("info", msg)
end
