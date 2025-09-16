\def\title{Moscow ML}
\input{macros}

@** Introduction.
This is a literate implementation of the runtime for Moscow ML.

So far, it seems\dots fine. There's little \emph{compelling} me to
write in \CWEB/ (as opposed to \WEB/).

@ It appears that \.{CWEB} assumes that structures are introduced as
|typedef struct {  } new_type|. When we try keeping |struct foo| as
if it were a type, then \.{CWEB} freaks out and formats things incorrectly.

@i mlvalues.w

@i config.w

@i m.w

@i s.w

@i misc.w

@i sys.w

@i io.w

@i interp.w


@** Index.