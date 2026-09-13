class_name BotNames
extends RefCounted

const NAMES := ["Ash", "Brook", "Cinder", "Dune", "Ember", "Flint", "Gale", "Harbor", "Iris", "Jet", "Kestrel", "Lumen",
	"Moss", "Nova", "Onyx", "Pike", "Quill", "Rook", "Slate", "Tarn", "Umber", "Vale", "Wren", "Yarrow", "Zephyr"]


static func pick(bot_id: int) -> String:
	return "[BOT] " + NAMES[posmod(-bot_id - 1, NAMES.size())]
