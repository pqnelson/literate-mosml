# Tutorial on CWEB

- You will write in "numbered paragraphs", which contains a text part
  and a code part. 
  - The text part uses TeX
  - The code part uses C
- Numbered paragraphs are introduced by `@` on a newline. Then it
  starts in TeX mode automatically until you tell it to get into code mode.
  - Numbered paragraphs with **names** use `@* Section name.` on its
    own line. Note the period is important and needed in the section name.
  - Starting a "part" `@** New Part Name.` which looks different on
    the table of contents, but just looks like a numbered paragraph
    starting on a new page.
  - Starting a "chapter" `@* New Chapter Name.` which looks different
    on the table of contents, but just looks like a numbered paragraph
    starting on a new page (equivalent to `@*0 New Chapter Name.`).
  - Starting a "section" `@*1 New Section Name.` which looks different
    on the table of contents, but looks like a numbered paragraph
    starting on a new page
  - For any other `n > 1`, we can have `@*n New Subsection Name.` and
    **will not** start on a new page.
- Un-named code segments starts after `@c`
  - Un-named code segments continue the previous code segment.
- Named code chunks start with `@<Name of code chunk@>=`
  - You can append more code to a named code chunk by just writing
    `@<Name of code chunk@>=...` again in a later numbered paragraph.
  - You can also make the numbered paragraph "just the named code chunk"
    by writing `@ @<Name of code chunk@>=...`
- You can refer to a named code chunk inside C code by writing 
  `@<Name of code chunk@>`. CTangle will splice in the contents of
  `@<Name of code chunk@>` when extracting the code.
- You can use `@(Name-of-file.c@>=...` or `@(Name-of-file.h@>=...` for
  named code chunks which describe the contents of `Name-of-file.c`
  (resp., `Name-of-file.h`).
- If you want to use `@` as a letter, you need to write it twice `@@`
  and CWEAVE will treat it as a single `@` letter.
  
# Odds and ends

- You can add an index entry by writing `@^Index entry@>`
  - Formatting the index entry can be done by `@^Entry name for sorting}{Prettyprinted index entry@>`
- You probably want to have a `macros.tex` file for TeX macros, and
  the first thing you'll want to do is have a `\input{macros}` before
  any named paragraph
- You also will probably want to include `\def\title{...}` to give a
  title to your piece
- You probably want a "main" file (we use `mosml.w`) and "include"
  files into it. This is done by writing a line `@i other-file.w` to include the
  contents of `other-file.w` into the "main" file.