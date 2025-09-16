@* Values.
This is a header file.

@(mlvalues.h@>=
#ifndef _mlvalues_
#define _mlvalues_


#include "config.h"
#include "misc.h"


@
Definitions

\bull |word|: Four bytes on 32 and 16 bit architectures,
        eight bytes on 64 bit architectures.
\bul |long|: A C long integer.
\bul |val|: The ML representation of something.  A long or a block or a pointer
       outside the heap.  If it is a block, it is the (encoded) address
       of an object.  If it is a long, it is encoded as well.
\bul |object|: Something allocated.  It always has a header and some
          fields or some number of bytes (a multiple of the word size).
\bul |field|: A word-sized val which is part of an object.
\bul |bp|: Pointer to the first byte of an object.  (a |char *|)
\bul |op|: Pointer to the first field of an object.  (a |value *|)
\bul |hp|: Pointer to the header of an object.  (a |char *|)
\bul |int32|: Four bytes on all architectures.

\medbreak\noindent%
  Remark: An object size is always a multiple of the word size, and at least
          one word plus the header.
\medbreak

\bull |bosize|: Size (in bytes) of the "bytes" part.
\bul |wosize|: Size (in words) of the "fields" part.
\bul |bhsize|: Size (in bytes) of the object with its header.
\bul |whsize|: Size (in words) of the object with its header.

\bull |hd|: A header.
\bul |tag|: The value of the tag field of the header.
\bul |color|: The value of the color field of the header.
         This is for use only by the GC.


@c
typedef long value;
typedef unsigned long header_t;
#ifdef SIXTEEN
typedef unsigned int mlsize_t;
#else
typedef unsigned long mlsize_t;
#endif
typedef unsigned int tag_t;             /* Actually, an unsigned char */
typedef unsigned long color_t;
typedef unsigned long mark_t;

@
@c
#ifdef SIXTYFOUR
typedef int int32;            /* Not portable, but checked by autoconf. */
typedef unsigned int uint32;  /* Seems like a reasonable assumption anyway. */
#else
typedef long int32;
typedef unsigned long uint32;
#endif

@
@c
/* Longs vs blocks. */
#define Is_long(x) @t\quad @>   (((x) & 1) == 1)
#define Is_block(x) @t\quad @>  (((x) & 1) == 0)

@
@c
/* Conversion macro names are always of the form  |to_from|. */
/* Example: |Val_long| as in "Val from long" or "Val of long". */
#define Val_long(x) @t\quad @>     (((long)(x) << 1) + 1)
#define Long_val(x) @t\quad @>     ((x) >> 1)
#define Max_long @t\quad @> ((long)((1L << (8 * sizeof(value) - 2)) - 1))
#define Min_long @t\quad @> ((long) -(1L << (8 * sizeof(value) - 2))) 
#define Val_int @t\quad @> Val_long
#define Int_val(x) @t\quad @> ((int) Long_val(x))

@ 
For 16-bit and 32-bit architectures:
$$\beginword
&\field{24}{\llap{bits\enspace}31\hfill10\enspace}&&\field{8}{\enspace9\hfill8\enspace}&&\field{8}{\enspace7\hfill0}\cr
\noalign{\hrule}
\\&wosize&\\&color&\\&tag&\\\cr
\noalign{\hrule}\endword$$
For 64-bit architectures:
$$\beginword
&\field{24}{\llap{bits\enspace}63\hfill10\enspace}&&\field{8}{\enspace9\hfill8\enspace}&&\field{8}{\enspace7\hfill0}\cr
\noalign{\hrule}
\\&wosize&\\&color&\\&tag&\\\cr
\noalign{\hrule}\endword$$
@c
#define Tag_hd(hd) @t\quad @> ((tag_t) ((hd) & 0xFF))
#define Wosize_hd(hd) @t\quad @> ((mlsize_t) ((hd) >> 10))

#define Hd_val(val) @t\quad @> (((header_t *) (val)) [-1])        /* Also an l-value. */
#define Hd_op(op) @t\quad @> (Hd_val (op))                        /* Also an l-value. */
#define Hd_bp(bp) @t\quad @> (Hd_val (bp))                        /* Also an l-value. */
#define Hd_hp(hp) @t\quad @> (* ((header_t *) (hp)))              /* Also an l-value. */
#define Hp_val(val) @t\quad @> ((char *) (((header_t *) (val)) - 1))
#define Hp_op(op) @t\quad @> (Hp_val (op))
#define Hp_bp(bp) @t\quad @> (Hp_val (bp))
#define Val_op(op) @t\quad @> ((value) (op))
#define Val_hp(hp) @t\quad @> ((value) (((header_t *) (hp)) + 1))
#define Op_hp(hp) @t\quad @> ((value *) Val_hp (hp))
#define Bp_hp(hp) @t\quad @> ((char *) Val_hp (hp))

@
@c
#define Num_tags @t\quad @> (1 << 8)
#ifdef SIXTYFOUR
#define Max_wosize @t\quad @> ((1L << 54) - 1)
#else
#ifdef SIXTEEN
#define Max_wosize @t\quad @> ((1 << 14) - 1)
#else
#define Max_wosize @t\quad @> ((1 << 22) - 1)
#endif
#endif

@
@c
#define Wosize_val(val) @t\quad @> (Wosize_hd (Hd_val (val)))
#define Wosize_op(op) @t\quad @> (Wosize_val (op))
#define Wosize_bp(bp) @t\quad @> (Wosize_val (bp))
#define Wosize_hp(hp) @t\quad @> (Wosize_hd (Hd_hp (hp)))
#define Whsize_wosize(sz)  @t\quad @> ((sz) + 1)
#define Wosize_whsize(sz) @t\quad @> ((sz) - 1)
#define Wosize_bhsize(sz) @t\quad @> ((sz) / sizeof (value) - 1)
#define Bsize_wsize(sz) @t\quad @> ((sz) * sizeof (value))
#define Wsize_bsize(sz) @t\quad @> ((sz) / sizeof (value))
#define Bhsize_wosize(sz) @t\quad @> (Bsize_wsize (Whsize_wosize (sz)))
#define Bhsize_bosize(sz) @t\quad @> ((sz) + sizeof (header_t))
#define Bosize_val(val) @t\quad @> (Bsize_wsize (Wosize_val (val)))
#define Bosize_op(op) @t\quad @> (Bosize_val (Val_op (op)))
#define Bosize_bp(bp) @t\quad @> (Bosize_val (Val_bp (bp)))
#define Bosize_hd(hd) @t\quad @> (Bsize_wsize (Wosize_hd (hd)))
#define Whsize_hp(hp) @t\quad @> (Whsize_wosize (Wosize_hp (hp)))
#define Whsize_val(val) @t\quad @> (Whsize_hp (Hp_val (val)))
#define Whsize_bp(bp) @t\quad @> (Whsize_val (Val_bp (bp)))
#define Whsize_hd(hd) @t\quad @> (Whsize_wosize (Wosize_hd (hd)))
#define Bhsize_hp(hp) @t\quad @> (Bsize_wsize (Whsize_hp (hp)))
#define Bhsize_hd(hd) @t\quad @> (Bsize_wsize (Whsize_hd (hd)))

@
@c
#ifdef MOSML_BIG_ENDIAN
#define Tag_val(val) @t\quad @> (((unsigned char *) (val)) [-1])
                                                 /* Also an l-value. */
#define Tag_hp(hp) @t\quad @> (((unsigned char *) (hp)) [sizeof(value)-1])
                                                 /* Also an l-value. */
#else
#define Tag_val(val) @t\quad @> (((unsigned char *) (val)) [-sizeof(value)])
                                                 /* Also an l-value. */
#define Tag_hp(hp) @t\quad @> (((unsigned char *) (hp)) [0])
                                                 /* Also an l-value. */
#endif

@
@c
/* The tag values MUST AGREE with compiler/Config.mlp: */

/* The Lowest tag for blocks containing no value. */
#define No_scan_tag @t\quad @> (Num_tags - 5)


/* 1- If |tag < No_scan_tag| : a tuple of fields.  */

/* Pointer to the first field. */
#define Op_val(x) @t\quad @> ((value *) (x))
/* Fields are numbered from 0. */
#define Field(x, i) @t\quad @> (((value *)(x)) [i])           /* Also an l-value. */

@
@c
/* A sequence of bytecodes */
typedef unsigned char * bytecode_t;

/* A sequence of real machine instruction addresses */
typedef void ** realcode_t;

@
@c
/* GCC 2.0 has labels as first-class values. We take advantage of that
   to provide faster dispatch than the "switch" statement. */

#if defined(__GNUC__) && __GNUC__ >= 2 && !defined(DEBUG)
#define DIRECT_JUMP
#endif

#if defined(DIRECT_JUMP) && defined(THREADED)
#define CODE @t\quad @> realcode_t
#else
#define CODE @t\quad @> bytecode_t
#endif

@
@c
#define Closure_wosize @t\quad @> 2
#define Closure_tag @t\quad @> (No_scan_tag - 2)
#define Code_val(val) @t\quad @> (((CODE *) (val)) [0])     /* Also an l-value. */
#define Env_val(val) @t\quad @> (Field(val, 1))               /* Also an l-value. */

@
@c
/* --- Reference cells are used in Moscow SML --- */

#define Reference_tag @t\quad @> (No_scan_tag - 1)

/* --- --- */


/* 2- If |tag >= No_scan_tag| : a sequence of bytes. */

/* Pointer to the first byte */
#define Bp_val(v) @t\quad @> ((char *) (v))
#define Val_bp(p) @t\quad @> ((value) (p))
/* Bytes are numbered from 0. */
#define Byte(x, i) @t\quad @> (((char *) (x)) [i])            /* Also an l-value. */
#define Byte_u(x, i) @t\quad @> (((unsigned char *) (x)) [i]) /* Also an l-value. */

/* Arrays of weak pointers.  Just like abstract things, but the GC will 
   reset each cell (during the weak phase, between marking and sweeping) 
   as the pointed-to object gets deallocated.  
*/
#define Weak_tag @t\quad @> No_scan_tag

/* Abstract things.  Their contents is not traced by the GC; therefore they
   must not contain any [value].
*/
#define Abstract_tag @t\quad @> (No_scan_tag + 1)

@
@c
/* Strings. */
#define String_tag @t\quad @> (No_scan_tag + 2)
#define String_val(x) @t\quad @> ((char *) Bp_val(x))

@
@c
/* Floating-point numbers. */
#define Double_tag @t\quad @> (No_scan_tag + 3)
#define Double_wosize @t\quad @> ((sizeof(double) / sizeof(value)))
#ifndef ALIGN_DOUBLE
#define Double_val(v) @t\quad @> (* (double *) (v))
#else
EXTERN double Double_val (value);
#endif
void Store_double_val (value,double);

@
@c
/* Finalized things.  Just like abstract things, but the GC will call the
   [|Final_fun|] before deallocation.
*/
#define Final_tag @t\quad @> (No_scan_tag + 4)
typedef void (*final_fun) @t\quad @> (value);
#define Final_fun(val) @t\quad @> (((final_fun *) (val)) [0]) /* Also an l-value. */


@
@c
/* 3- Atoms are 0-tuples.  They are statically allocated once and for all. */

EXTERN header_t first_atoms[];
#define Atom(tag) @t\quad @> (Val_hp (&(first_atoms [tag])))
#define Is_atom(v) @t\quad @> (v >= Atom(0) && v <= Atom(255))

@
@c
/* Booleans are atoms tagged 0 or 1 */

#define Val_bool(x) @t\quad @> Atom((x) != 0)
#define Bool_val(x) @t\quad @> Tag_val(x)
#define Val_false @t\quad @> Atom(0)
#define Val_true @t\quad @> Atom(1)

@
@c
/* The unit value is the atom tagged 0 */

#define Val_unit Atom(0)

/*  SML option values: Must match compiler/Types.sml: */

#define NONE @t\quad @> Atom(0)
#define SOMEtag @t\quad @> (1) 

#endif /* mlvalues */
