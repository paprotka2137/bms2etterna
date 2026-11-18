JUDGMENT SKINS (7k)
===================

Every folder in here is one judgment skin. Pick it in Player Options,
"Judgment Skin" (first page, under the noteskin). "Text (default)" is the
usual LR2 style text, used when no skin is picked.

Folders whose name starts with "_" or "." are ignored.


LAYOUT
------

  Themes/ECFN etterna/JudgmentSkins/
      My Skin/
          PGREAT.png
          GREAT.png
          GOOD.png
          BAD.png
          POOR.png
          EMPTYPOOR.png   (optional)
          COOL.png        (optional, O2Jam charts)
          MISS.png        (optional, O2Jam charts)

The folder name is the name shown in Player Options.


FILE NAMES
----------

  PGREAT     perfect great
  GREAT      great
  GOOD       good
  BAD        bad (also the LR2 BAD that leaves the note in the lane)
  POOR       poor / miss
  EMPTYPOOR  empty poor (a press with no note to hit). Uses POOR if missing.
  COOL       O2Jam COOL. Uses PGREAT if missing.
  MISS       O2Jam MISS. Uses POOR if missing.
  (O2Jam GOOD and BAD use GOOD and BAD.)

- Upper or lower case both work: PGREAT.png, pgreat.png, PGreat.png.
- png, jpg, jpeg, gif and bmp are read. Use png for transparency.
- Anything after the name is allowed, so "PGREAT 1x3.png" or
  "POOR_red.png" still count. If two files match, the first by name wins.
- A judgment with no picture in the skin is shown as text, so a skin can
  hold just a few pictures.


ANIMATED PICTURES
-----------------

To animate a judgment, put the frames side by side in one picture and add
"<columns>x<rows>" to the file name, like Etterna noteskins:

  PGREAT 1x3.png    3 frames stacked top to bottom
  PGREAT 3x1.png    3 frames left to right

The animation starts on the first frame on every hit and loops, at 0.1 s
per frame. To set the speed, add the time of one whole loop in ms:

  PGREAT 1x6 100ms.png    all 6 frames in 100 ms

A frame can be empty (fully transparent) to make the judgment blink.


HIGH RESOLUTION PICTURES
------------------------

The theme is laid out for a 480 px tall screen, so a picture made for
1080p looks about twice too big. Add "(res WIDTHxHEIGHT)" to the file
name to draw the whole picture at that size while keeping its detail:

  PGREAT 1x6 100ms (res 104x300).png

WIDTH x HEIGHT is the size of the whole file (all frames), not one frame.


SIZE AND POSITION
-----------------

Pictures are drawn at their own size, centered on the judgment position.
About 200 to 400 px wide is a good start. Move or resize them in game with
Customize Gameplay (keys 1 and 2), the same as the text judgment.

The pop and fade follows the "Judgement Animations" setting in Theme
Options. The picture's own colors are kept (no tint).


TO SEE CHANGES
--------------

New folders show up the next time Player Options opens. Changed pictures
in a skin you already played may need a game restart (textures are cached).

The "Sample" folder is an example made from plain text. Delete it if you
don't want it in the list.


ECFN SKINS
----------

The "ECFN ..." folders are the judgments of the ECFN beatoraja skin, one
folder per variant in Themes/ECFN/play/judge (and judge/legacy), cut into
the files above. As in ECFN, PGREAT is the color cycling "GREAT", GREAT is
the orange blinking one, and EMPTYPOOR is "FAIL". ECFN has no O2Jam
judgments, so COOL and MISS use PGREAT and POOR.

The ECFN readme forbids redistributing its images and using them on other
platforms, so keep these folders to yourself: don't put them in packs you
share.
