- Named code chunks are used for "statements", and should have a
  semicolon following it
- Code chunk names usually begin with an imperative verb ("Sort the array",
  "Find the smallest value", "Lookup the address of the inode", etc.)
  - One exception which Knuth suggests: the structure of a file should
    look like:
    ```
    @<Headers for [file]@>@;
    
    @<Types for [file]@>@;
    
    @<Functions for [file]@>@;
    ```
    (The `@;` tells CWEAVE to use "phantom semicolons" to pretend
    there is a semicolon for line-break purposes.)
- People remember at most 4 things, so a code chunk should limit the
  number of things done to at most 4 things