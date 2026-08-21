class_name MatchUi
extends RefCounted
## Rules about what the match shows, kept away from the autoloads.
##
## This exists so it can be TESTED. Everything that knows about the match
## — world.gd, main.gd — reaches an autoload, and a `--script` test run
## cannot load a script that does. A rule that cannot be tested is a rule
## that quietly goes wrong, which is what happened here.

## Does the end-of-battle table belong on screen in this phase?
##
## Say it as the one phase it IS for, never as a list of the phases it is
## not. It was written the other way round — hide for LOBBY, SETUP and
## BATTLE — and so said nothing about IDLE, which is precisely where a
## battle lands when it finishes and no new one follows (the loop turned
## off, or the last human gone). The table stayed up for good.
##
## Written this way a new phase is handled before it exists: anything
## that is not END hides the table.
static func final_table_shows(phase: String) -> bool:
	return phase == "END"
