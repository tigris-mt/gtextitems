local S = minetest.get_translator()
local F = minetest.formspec_escape

local has_doc = minetest.get_modpath("doc_items")

gtextitems = {}

-- gtextitem item group
-- This item is blank (stackable, no metadata yet).
gtextitems.GROUP_BLANK = 1
-- This item is written (not stackable, has metadata).
gtextitems.GROUP_WRITTEN = 2

if has_doc then
	doc.sub.items.register_factoid(nil, "use", function(itemstring, def)
		local ret = {}
		local g = minetest.get_item_group(itemstring, "gtextitem")
		if g > 0 then
			table.insert(ret, S"This item can be written in when used (punched with).")
			if g == gtextitems.GROUP_WRITTEN then
				table.insert(ret, S("It can be copied by crafting with another empty @1.", minetest.registered_items[def._gtextitems_def.itemname].description))
			end
		end
		return table.concat(ret, "\n")
	end)
end

-- When punching, display the formspec.
function gtextitems.on_use(stack, player)
	local playername = player:get_player_name()

	local gtm = gtextitems.get_item(stack)
	if not gtm then
		return stack
	end

	local formspec = ""
	.. "size[8,8]"
	.. "real_coordinates[true]"
	.. ("field[0.1,0.35;7.8,0.5;title;%s;%s]"):format(F(S"Title:"), F(gtm.title))
	.. "field_close_on_enter[title;false]"
	.. ("textarea[0.1,1.2;7.8,6;text;%s;%s]"):format(F(S"Text:"), F(gtm.text))
	.. "field_close_on_enter[text;false]"
	-- Only display the auther when it is set.
	.. ((minetest.get_item_group(stack:get_name(), "gtextitem") == gtextitems.GROUP_BLANK or #gtm.author == 0) and "" or ("label[0.1,7.5;%s]"):format(F(S("Last written by @1", gtm.author))))
	.. ("button_exit[6.75,7.4;1,0.5;save;%s]"):format(F(S"Write"))

	minetest.show_formspec(playername, "gtextitems:formspec", formspec)
	return stack
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if formname ~= "gtextitems:formspec" then
		return
	end

	if not fields.save then
		return
	end

	-- The wielded item will be the gtextitem.
	local wielded = player:get_wielded_item()
	-- Ensure it's a valid item.
	if not gtextitems.get_item(wielded) then
		return
	end

	-- Create a new stack of the written item.
	local def = minetest.registered_items[wielded:get_name()]._gtextitems_def
	local stack = ItemStack(def.writtenname)

	stack = gtextitems.set_item(stack, {
		author = player:get_player_name(),
		title = fields.title,
		text = fields.text,
	})

	-- Take one item from wielded (if blank, then one from the stack, otherwise the whole written stack).
	wielded:take_item(1)
	player:set_wielded_item(wielded)

	-- Add the edited item. If it was originally a written item or single item stack, this will simply replace the item removed from wielded earlier.
	minetest.add_item(player:get_pos(), player:get_inventory():add_item("main", stack))
	return true
end)

-- gtextitem data structure.
local default = {
	-- Who last modified this? If blank, then disregard. Should be multiple words if "written" by an NPC.
	author = "",
	title = "Untitled",
	text = "",
}

-- Add data to a gtextitem and sets description.
function gtextitems.set_item(stack, data)
	stack:get_meta():set_string("gtextitem", minetest.serialize(data))
	stack:get_meta():set_string("description", S("'@1' by @2", gtextitems.get_item(stack).title, gtextitems.get_item(stack).author))
	return stack
end

-- Get a gtextitem's data. Returns nil if the item is not a gtextitem.
function gtextitems.get_item(stack)
	if minetest.get_item_group(stack:get_name(), "gtextitem") == 0 then
		return nil
	end

	local d = stack:get_meta():get_string("gtextitem")
	return table.combine(default, (#d > 0) and minetest.deserialize(d) or {})
end

-- Sets a gtextitem written node's data.
function gtextitems.set_node(pos, data)
	local nn = minetest.get_node(pos).name

	-- Only written nodes can be set.
	if minetest.get_item_group(nn, "gtextitem") ~= gtextitems.GROUP_WRITTEN then
		minetest.log("warning", ("Tried to gtextitems.set_node invalid node (%s) at (%s)."):format(nn, minetest.pos_to_string(pos)))
		return
	end

	-- Construct "fake" stack.
	local stack = gtextitems.set_item(ItemStack(nn), data)

	local meta = minetest.get_meta(pos)
	meta:set_string("gtextitem", stack:get_meta():get_string("gtextitem"))
	meta:set_string("infotext", stack:get_meta():get_string("description"))

	local gtm = gtextitems.get_item(stack)
	meta:set_string("formspec", "size[8,8]"
		.. "real_coordinates[true]"
		.. ("label[0.1,0.35;%s]"):format(F(gtm.title))
		.. ("textarea[0.1,1.2;7.8,6.2;;;%s]"):format(F(gtm.text))
		.. ((#gtm.author == 0) and "" or ("label[0.1,7.5;%s]"):format(F(S("Last written by @1", gtm.author))))
	)
end

local function register_node(name, def)
	-- Override def with functions to save and load metadata when converting between item and node.
	local def = table.combine(def, {
		preserve_metadata = function(pos, oldnode, oldmeta, drops)
			for _,drop in ipairs(drops) do
				if minetest.get_item_group(drop:get_name(), "gtextitem") == gtextitems.GROUP_WRITTEN then
					drop:get_meta():set_string("gtextitem", oldmeta.gtextitem)
					drop:get_meta():set_string("description", oldmeta.infotext)
				end
			end
		end,

		after_place_node = function(pos, _, stack)
			-- Don't set any metadata if this is just a blank item.
			if minetest.get_item_group(stack:get_name(), "gtextitem") == gtextitems.GROUP_BLANK then
				return
			end
			gtextitems.set_node(pos, gtextitems.get_item(stack))
		end,
	})
	minetest.register_node(":" .. name, def)
end

function gtextitems.register(name, def)
	def = table.combine({
		-- Item names.
		itemname = name,
		writtenname = name .. "_written",

		-- Register as a node?
		node = false,
	}, def, {
		-- Base item override.
		item = table.combine({
			description = S"Writable Item",
			on_use = gtextitems.on_use,
		}, def.item or {}),

		-- Additional written item overrides.
		written = table.combine({
			description = S"Written Item",
			on_use = gtextitems.on_use,
			stack_max = 1,
		}, def.written or {}),
	})

	def.item._gtextitems_def = def

	def.item.groups = table.combine({
		gtextitem = gtextitems.GROUP_BLANK,
	}, def.item.groups or {})

	def.written.groups = table.combine(def.item.groups, {
		gtextitem = gtextitems.GROUP_WRITTEN,
	}, def.written.groups or {})

	if def.node then
		register_node(def.itemname, def.item)
		register_node(def.writtenname, table.combine(def.item, def.written))
	else
		minetest.register_craftitem(":" .. def.itemname, def.item)
		minetest.register_craftitem(":" .. def.writtenname, table.combine(def.item, def.written))
	end

	-- Register shapeless copying recipe.
	minetest.register_craft{
		output = def.writtenname,
		type = "shapeless",
		recipe = {def.itemname, def.writtenname},
	}

	-- When copy-crafting, copy metadata and restore the old written item.
	minetest.register_on_craft(function(stack, player, old_grid, craft_inv)
		if stack:get_name() ~= def.writtenname then
			return
		end

		-- Locate the item to copy.
		for i=1,craft_inv:get_size("craft") do
			if old_grid[i]:get_name() == def.writtenname then
				stack = gtextitems.set_item(stack, gtextitems.get_item(old_grid[i]))
				craft_inv:set_stack("craft", i, old_grid[i])
				break
			end
		end

		return stack
	end)

	-- Same as above, but for prediction. Don't restore the old written item.
	minetest.register_craft_predict(function(stack, player, old_grid, craft_inv)
		if stack:get_name() ~= def.writtenname then
			return
		end

		for i=1,craft_inv:get_size("craft") do
			if old_grid[i]:get_name() == def.writtenname then
				stack = gtextitems.set_item(stack, gtextitems.get_item(old_grid[i]))
				break
			end
		end

		return stack
	end)
end
