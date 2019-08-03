local S = minetest.get_translator()
local F = minetest.formspec_escape

local has_doc = minetest.get_modpath("doc_items")

gtextitems = {}

gtextitems.GROUP_BLANK = 1
gtextitems.GROUP_WRITTEN = 2

if has_doc then
	doc.sub.items.register_factoid(nil, "use", function(itemstring, def)
		local ret = {}
		local g = minetest.get_item_group(itemstring, "gtextitem")
		if g > 0 then
			table.insert(ret, S"This item can be written in when used (punched with).")
			if g == gtextitems.GROUP_WRITTEN then
				table.insert(ret, S("It can be copied by crafting with another empty @1.", minetest.registered_nodes[def._gtextitems_def.itemname].description))
			end
		end
		return table.concat(ret, "\n")
	end)
end

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
	.. ("button_exit[3.5,7.4;1,0.5;save;%s]"):format(F(S"Write"))

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

	local wielded = player:get_wielded_item()
	if not gtextitems.get_item(wielded) then
		return
	end

	local def = minetest.registered_items[wielded:get_name()]._gtextitems_def
	local stack = ItemStack(def.writtenname)

	stack = gtextitems.set_item(stack, {
		author = player:get_player_name(),
		title = fields.title,
		text = fields.text,
	})

	wielded:take_item(1)
	player:set_wielded_item(wielded)
	minetest.add_item(player:get_pos(), player:get_inventory():add_item("main", stack))
	return true
end)

local default = {
	author = "Unknown",
	title = "Untitled",
	text = "",
}

function gtextitems.set_item(stack, data)
	stack:get_meta():set_string("gtextitem", minetest.serialize(data))
	stack:get_meta():set_string("description", S("'@1' by @2", gtextitems.get_item(stack).title, gtextitems.get_item(stack).author))
	return stack
end

function gtextitems.get_item(stack)
	if minetest.get_item_group(stack:get_name(), "gtextitem") == 0 then
		return nil
	end

	local d = stack:get_meta():get_string("gtextitem")
	return table.combine(default, (#d > 0) and minetest.deserialize(d) or {})
end

function gtextitems.register(name, def)
	def = table.combine({
		itemname = name,
		writtenname = name .. "_written",
	}, def, {
		item = table.combine({
			description = S"Writable Item",
			on_use = gtextitems.on_use,
		}, def.item or {}),

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

	minetest.register_craftitem(def.itemname, def.item)
	minetest.register_craftitem(def.writtenname, table.combine(def.item, def.written))
end
