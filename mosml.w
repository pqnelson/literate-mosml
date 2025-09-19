\def\title{Moscow ML}
\input{macros}

@** Introduction.
This is a literate implementation of the runtime for Moscow ML.

So far, it seems\dots fine. There's little \emph{compelling} me to
write in \CWEB/ (as opposed to \WEB/).

@ It appears that \.{CWEB} assumes that structures are introduced as
|typedef struct {  } new_type|. When we try keeping |struct foo| as
if it were a type, then \.{CWEB} freaks out and formats things incorrectly.

@(version.h@>=
#define VERSION "0.8e for Moscow ML"

@i mlvalues.w

@i config.w

@i reverse.w

@i unalignd.w

@i m.w

@i s.w

@i misc.w

@i sys.w

@i io.w

@i instruct.w

@i exec.w

@i interp.w

@i globals.w

@i fail.w

@i gc.w

@i debugger.w

@i gc-ctrl.w

@i freelist.w

@i runtime.w

@i stacks.w

@i roots.w

@i minor-gc.w

@i major-gc.w

@i memory.w

@i alloc.w

@i main.w

@i hash.w

@i io.w

@i interncp.w

@i intern.w

@i externcp.w

@i extern.w

@i intext.w

@i ints.w

@i floats.w

@i str.w

@i prims.w

@i meta.w

@i compare.w

@i callback.w

@i graph.w

@i unix.w

@i mosml-code.w

@i fix-code.w

@i dynlib.w

@i signals.w

@i expand.w

@i md5sum.w

@i msdos.w

@i lexing.w

@i parsing.w

@** Index.