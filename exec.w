@* Format of executable bytecode fields.

{\obeylines\obeyspaces\tt

offset 0 --->  initial junk
                   code block
                   data block
                   symbol table
                   debug infos
                   trailer
 end of file --->
\par}

@(exec.h@>=
/* Structure of the trailer: five 32-bit, unsigned integers, big endian */

#define TRAILER_SIZE 20

struct exec_trailer {
  unsigned long code_size;      /* Size of the code block (in bytes) */
  unsigned long data_size;      /* Size of the global data table (bytes) */
  unsigned long symbol_size;    /* Size of the symbol table (bytes) */
  unsigned long debug_size;     /* Size of the debug infos (bytes) */
  unsigned long magic;          /* A magic number */
};

@ @(exec.h@>=
/* Magic number for this release */

#define EXEC_MAGIC 0x4d4c3038   /* "ML08" */
