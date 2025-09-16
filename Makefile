WEAVE=cweave -u
FILE=mosml
TEX=pdftex
TWILL=ctwill

all:
	$(WEAVE) $(FILE).w - $(FILE)
	$(TEX) $(FILE)
	$(TEX) $(FILE)

twill:
	$(TWILL) $(FILE).w - $(FILE)
	$(TWILL) $(FILE).w - $(FILE)
	$(TEX) $(FILE)
	ctwill-refsort < $(FILE).ref > $(FILE).sref
	$(TEX) $(FILE)
	ctwill-twinx $(FILE).x > index.tex