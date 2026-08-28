Place up to 16 recorded mouth-click variations in this folder as `.ogg`, `.wav`, or `.mp3` files.

The client discovers and registers them as the `mouth_click` spatial sound when the game world
starts. File names are sorted before registration, so multiplayer clients with the same checkout
use the same stable variation set. Until a recording exists, development uses a temporary click
from the existing asset bundle so the complete feature remains testable.
