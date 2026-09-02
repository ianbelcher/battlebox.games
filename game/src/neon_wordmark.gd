class_name NeonWordmark
extends TextureRect
## THE NAME OF THE GAME: the neon sign from the intro video, traced out of
## the film itself.
##
## The intro ends on a Minecraft field with BattleBox standing in it as a
## neon sign — a heavy connected script in glass tube, white at the core,
## pink outside and blue within. The front page said it in the same plain
## sans as the settings underneath, which is the game introducing itself
## in a voice it does not have anywhere else.
##
## AND IT IS NOT A TYPEFACE. That was tried: a dozen open script faces
## were set against the sign and the closest was picked. Put side by side
## with the real thing it is plainly not the real thing — the sign was
## built and lit in Minecraft and the shapes are its own, so no font is
## going to be them. The letterforms here are the sign's, lifted out of
## the video by tools/make_wordmark.py, which has the how and the why.
##
## So this is a picture, and the only thing this file does is put it on
## the screen at the right size. That is the point: nothing here can drift
## away from the sign, because it IS the sign.
##
## Re-make it with:
##
##     python3 tools/make_wordmark.py web/demo.mp4 game/assets/ui/wordmark.png

const ART := "res://assets/ui/wordmark.png"

## How wide the wordmark is, in design pixels. The height follows from the
## artwork's own proportions — a wordmark squashed to fit a box is worse
## than no wordmark.
const WIDTH := 520

func _init() -> void:
	texture = load(ART)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## `menu_scale` is the scale every other control on the screen is built
## at; WIDTH is what it multiplies.
func setup(menu_scale: float) -> NeonWordmark:
	var wide := UiTheme.px(WIDTH, menu_scale)
	var ratio := 0.25
	if texture != null and texture.get_width() > 0:
		ratio = float(texture.get_height()) / float(texture.get_width())
	custom_minimum_size = Vector2(wide, wide * ratio)
	return self
