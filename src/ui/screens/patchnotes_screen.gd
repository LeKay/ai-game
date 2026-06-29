## Patchnotes Screen — overlay shown from main menu.
##
## Loads every `*.md` file from `res://docs/patchnotes/`, sorted newest-first
## (descending by filename), converts a small Markdown subset to BBCode, and
## renders the concatenated content into a scrollable RichTextLabel.
##
## Closed via the X button or Escape.

extends CanvasLayer

signal closed()

const PATCHNOTES_DIR: String = "res://docs/patchnotes/"

@onready var body: RichTextLabel = %Body
@onready var close_button: Button = %CloseButton
@onready var scroll: ScrollContainer = %Scroll


func _ready() -> void:
	close_button.pressed.connect(_close)
	body.text = _build_bbcode()
	scroll.scroll_vertical = 0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	closed.emit()
	queue_free()


# ── Loading ─────────────────────────────────────────────────────────────────

func _build_bbcode() -> String:
	var files: PackedStringArray = _list_patchnote_files()
	if files.is_empty():
		return "[i]Keine Patchnotes gefunden in %s[/i]" % PATCHNOTES_DIR

	# Newest first (filenames are version-ordered like v0.1.0.md, v0.2.0.md).
	var sorted: Array = Array(files)
	sorted.sort()
	sorted.reverse()

	var parts: PackedStringArray = PackedStringArray()
	for i in sorted.size():
		var file_name: String = sorted[i]
		var text: String = _read_file(PATCHNOTES_DIR.path_join(file_name))
		if text.is_empty():
			continue
		if i > 0:
			parts.append("\n[color=#666666]──────────────────────────[/color]\n")
		parts.append(_markdown_to_bbcode(text))
	return "\n".join(parts)


func _list_patchnote_files() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(PATCHNOTES_DIR)
	if dir == null:
		push_warning("[Patchnotes] cannot open %s" % PATCHNOTES_DIR)
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.to_lower().ends_with(".md"):
			out.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _read_file(path: String) -> String:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


# ── Markdown → BBCode (small subset) ────────────────────────────────────────
#
# Supported:
#   # H1            → big bold heading
#   ## H2           → medium bold heading
#   ### H3          → small bold heading
#   - item / * item → bullet
#   **bold**        → [b]bold[/b]
#   *italic*        → [i]italic[/i]
#   `code`          → [code]code[/code]
#
# Anything else passes through as plain text (BBCode-escaped).

func _markdown_to_bbcode(md: String) -> String:
	var lines: PackedStringArray = md.split("\n")
	var out: PackedStringArray = PackedStringArray()
	for raw_line in lines:
		var line: String = raw_line
		var stripped: String = line.strip_edges(true, false)

		if stripped.begins_with("### "):
			var t: String = _inline_md(_escape_bbcode(stripped.substr(4)))
			out.append("[b][font_size=18]%s[/font_size][/b]" % t)
		elif stripped.begins_with("## "):
			var t2: String = _inline_md(_escape_bbcode(stripped.substr(3)))
			out.append("\n[b][color=#e6c97a][font_size=22]%s[/font_size][/color][/b]" % t2)
		elif stripped.begins_with("# "):
			var t3: String = _inline_md(_escape_bbcode(stripped.substr(2)))
			out.append("\n[b][color=#f0d590][font_size=28]%s[/font_size][/color][/b]" % t3)
		elif stripped.begins_with("- ") or stripped.begins_with("* "):
			var t4: String = _inline_md(_escape_bbcode(stripped.substr(2)))
			out.append("  • %s" % t4)
		elif stripped == "":
			out.append("")
		else:
			out.append(_inline_md(_escape_bbcode(line)))
	return "\n".join(out)


## Escapes BBCode-significant characters so user content cannot inject tags.
func _escape_bbcode(s: String) -> String:
	return s.replace("[", "[lb]")


## Replaces inline Markdown markers (**bold**, *italic*, `code`) with BBCode.
## Operates AFTER bbcode escaping so the marker characters are still intact.
func _inline_md(s: String) -> String:
	var result: String = s
	# Bold first (so ** doesn't collide with single *).
	result = _replace_paired(result, "**", "[b]", "[/b]")
	result = _replace_paired(result, "*", "[i]", "[/i]")
	result = _replace_paired(result, "`", "[code]", "[/code]")
	return result


## Replace pairs of `marker` with open_tag/close_tag, alternating.
func _replace_paired(s: String, marker: String, open_tag: String, close_tag: String) -> String:
	var out := ""
	var i := 0
	var open := true
	while i < s.length():
		var hit: int = s.find(marker, i)
		if hit < 0:
			out += s.substr(i)
			break
		out += s.substr(i, hit - i)
		out += open_tag if open else close_tag
		open = not open
		i = hit + marker.length()
	return out
