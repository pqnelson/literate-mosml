@** The bytecode interpreter.
The header is mercifully short.

@(interp.h@>=
#include "mlvalues.h"

EXTERN value interprete(int mode, bytecode_t bprog, int code_size, CODE* rprog);
EXTERN value callback(value closure, value arg);
EXTERN value callback2(value closure, value arg1, value arg2);
EXTERN value callback3(value closure, value arg1, value arg2, value arg3);

@* The bytecode interpreter.
@(interp.c@>=
#include <math.h>
#include <setjmp.h>
#include <stdlib.h>

#include "alloc.h"
#include "debugger.h"
#include "fail.h"
#include "instruct.h"
#include "memory.h"
#include "minor_gc.h"
#include "misc.h"
#include "mlvalues.h"
#include "prims.h"
#include "signals.h"
#include "stacks.h"
#include "str.h"
#include "unalignd.h"
#include "interp.h"
#include "expand.h"
#include "globals.h"
#ifdef HAS_UI
#include "ui.h"
#endif

#ifdef DEBUG
static long icount = 0;
static void stop_here (void) {}
#endif

@ Registers for the abstract machine:
\bull |pc|         the code pointer
\bul |sp|         the stack pointer (grows downward)
\bul |accu|       the accumulator
\bul |env|        heap-allocated environment
\bul |trapsp|     pointer to the current trap frame
\bul |extra_args| number of extra arguments provided by the caller

Note that |sp| is a local copy of the global variable |extern_sp|.

@c
#define null_env @[Atom(0)@]
/* The empty environment */

typedef unsigned char opcode_t; /* The type of bytecode instructions */

@ |byte_raise_break_exn| raises the Interrupt exception
   (|GETGLOBAL| takes a long (4B) arg) 

   |byte_callback[123]_code| do callbacks from C to ML code:
   ``POP, 1, 0'' means |pop(1)|

@c
#if defined(MOSML_BIG_ENDIAN) && !defined(ALIGNMENT)
static opcode_t byte_raise_break_exn[] =
       { GETGLOBAL, 0, 0, 0, EXN_INTERRUPT, RAISE };
static opcode_t byte_callback1_code[] = { ACC1, APPLY1, POP, 0, 1, STOP };
static opcode_t byte_callback2_code[] = { ACC2, APPLY2, POP, 0, 1, STOP };
static opcode_t byte_callback3_code[] = { ACC3, APPLY3, POP, 0, 1, STOP };
#else
static opcode_t byte_raise_break_exn[] =
       { GETGLOBAL, EXN_INTERRUPT, 0, 0, 0, RAISE };
static opcode_t byte_callback1_code[] = { ACC1, APPLY1, POP, 1, 0, STOP };
static opcode_t byte_callback2_code[] = { ACC2, APPLY2, POP, 1, 0, STOP };
static opcode_t byte_callback3_code[] = { ACC3, APPLY3, POP, 1, 0, STOP };
#endif /* |defined(MOSML_BIG_ENDIAN) && !defined(ALIGNMENT)| */
#define RAISE_CODE_LEN 6
#define CALLBACK_CODE_LEN 6

CODE @t\enspace @> callback1_code;		/* Set by interprete on initialization */
CODE @t\enspace @> callback2_code;
CODE @t\enspace @> callback3_code;

@ GC interface.

@c
#define Setup_for_gc { sp -= 2; sp[0] = accu; sp[1] = env; extern_sp = sp; }
#define Restore_after_gc { accu = sp[0]; env = sp[1]; sp += 2; }
#define Setup_for_c_call { *--sp = env; extern_sp = sp; }
#define Restore_after_c_call { sp = extern_sp; env = *sp++; }

@*1 The interpreter itself.

\bull |mode| = mode (0=init, 1=bytecode exec, 2=code exec)
\bul |bprog| = a bytecode array pointer (used in mode 1)
\bul |code_size| = the bytecode length
\bul |rprog| = a code pointer pointer (input in mode 2; output in mode 1)

@(interp.c@>=
EXTERN value interprete(int mode, bytecode_t bprog, int code_size, CODE* rprog)
{

  @<Declare register variables for the abstract machine@>@;
  value env;
  int extra_args;
  struct longjmp_buffer * initial_external_raise;
  int initial_sp_offset;
  value * initial_c_roots_head;
  struct longjmp_buffer raise_buf;
  value * modify_dest, modify_newval;
  value tmp;
  int cur_instr;
  double dtmp;

#ifdef DIRECT_JUMP
  static void * jumptable[] = {
#   include "jumptbl.h"
  };
#endif

@ @(jumptbl.h@>=
  &&lbl_CONSTBYTE,
  &&lbl_CONSTSHORT,
  &&lbl_SWITCH,
  &&lbl_BRANCH,
  &&lbl_BRANCHIF,
  &&lbl_BRANCHIFNOT,
  &&lbl_POPBRANCHIFNOT,
  &&lbl_BRANCHIFNEQTAG,
  &&lbl_BRANCHIFEQ,
  &&lbl_BRANCHIFNEQ,
  &&lbl_BRANCHIFLT,
  &&lbl_BRANCHIFGT,
  &&lbl_BRANCHIFLE,
  &&lbl_BRANCHIFGE,
  &&lbl_BRANCHINTERVAL,
  &&lbl_C_CALL1,
  &&lbl_C_CALL2,
  &&lbl_C_CALL3,
  &&lbl_C_CALL4,
  &&lbl_C_CALL5,
  &&lbl_C_CALLN,
  &&lbl_MAKEBLOCK,
  &&lbl_MAKEBLOCK1,
  &&lbl_MAKEBLOCK2,
  &&lbl_MAKEBLOCK3,
  &&lbl_MAKEBLOCK4,
  &&lbl_TAGOF,
  &&lbl_ACCESS,
  &&lbl_ACC0,
  &&lbl_ACC1,
  &&lbl_ACC2,
  &&lbl_ACC3,
  &&lbl_ACC4,
  &&lbl_ACC5,
  &&lbl_ACC6,
  &&lbl_ACC7,
  &&lbl_PUSHACC,
  &&lbl_PUSHACC0,
  &&lbl_PUSHACC1,
  &&lbl_PUSHACC2,
  &&lbl_PUSHACC3,
  &&lbl_PUSHACC4,
  &&lbl_PUSHACC5,
  &&lbl_PUSHACC6,
  &&lbl_PUSHACC7,
  &&lbl_ENVACC,
  &&lbl_ENV1,
  &&lbl_ENV2,
  &&lbl_ENV3,
  &&lbl_ENV4,
  &&lbl_ENV5,
  &&lbl_ENV6,
  &&lbl_ENV7,
  &&lbl_PUSHENVACC,
  &&lbl_PUSHENV1,
  &&lbl_PUSHENV2,
  &&lbl_PUSHENV3,
  &&lbl_PUSHENV4,
  &&lbl_PUSHENV5,
  &&lbl_PUSHENV6,
  &&lbl_PUSHENV7,
  &&lbl_PUSH_ENV1_APPLY1,
  &&lbl_PUSH_ENV1_APPLY2,
  &&lbl_PUSH_ENV1_APPLY3,
  &&lbl_PUSH_ENV1_APPLY4,
  &&lbl_PUSH_ENV1_APPTERM1,
  &&lbl_PUSH_ENV1_APPTERM2,
  &&lbl_PUSH_ENV1_APPTERM3,
  &&lbl_PUSH_ENV1_APPTERM4,
  &&lbl_PUSHATOM,
  &&lbl_ATOM,
  &&lbl_PUSHATOM0,
  &&lbl_ATOM0,
  &&lbl_ATOM1,
  &&lbl_ATOM2,
  &&lbl_ATOM3,
  &&lbl_ATOM4,
  &&lbl_ATOM5,
  &&lbl_ATOM6,
  &&lbl_ATOM7,
  &&lbl_ATOM8,
  &&lbl_ATOM9,
  &&lbl_CONSTINT,
  &&lbl_PUSHCONSTINT,
  &&lbl_CONST0,
  &&lbl_CONST1,
  &&lbl_CONST2,
  &&lbl_CONST3,
  &&lbl_PUSHCONST0,
  &&lbl_PUSHCONST1,
  &&lbl_PUSHCONST2,
  &&lbl_PUSHCONST3,
  &&lbl_GETFIELD,
  &&lbl_GETFIELD0,
  &&lbl_GETFIELD1,
  &&lbl_GETFIELD2,
  &&lbl_GETFIELD3,
  &&lbl_GETFIELD0_0,
  &&lbl_GETFIELD0_1,
  &&lbl_GETFIELD1_0,
  &&lbl_GETFIELD1_1,
  &&lbl_SETFIELD,
  &&lbl_SETFIELD0,
  &&lbl_SETFIELD1,
  &&lbl_SETFIELD2,
  &&lbl_SETFIELD3,
  &&lbl_GETGLOBAL,
  &&lbl_PUSH_GETGLOBAL,
  &&lbl_PUSH_GETGLOBAL_APPLY1,
  &&lbl_PUSH_GETGLOBAL_APPLY2,
  &&lbl_PUSH_GETGLOBAL_APPLY3,
  &&lbl_PUSH_GETGLOBAL_APPLY4,
  &&lbl_PUSH_GETGLOBAL_APPTERM1,
  &&lbl_PUSH_GETGLOBAL_APPTERM2,
  &&lbl_PUSH_GETGLOBAL_APPTERM3,
  &&lbl_PUSH_GETGLOBAL_APPTERM4,
  &&lbl_SETGLOBAL,
  &&lbl_PUSH_RETADDR,
  &&lbl_APPLY,
  &&lbl_APPLY1,
  &&lbl_APPLY2,
  &&lbl_APPLY3,
  &&lbl_APPLY4,
  &&lbl_APPTERM,
  &&lbl_APPTERM1,
  &&lbl_APPTERM2,
  &&lbl_APPTERM3,
  &&lbl_APPTERM4,
  &&lbl_RESTART,
  &&lbl_GRAB,
  &&lbl_RETURN1,
  &&lbl_RETURN2,
  &&lbl_RETURN,
  &&lbl_CLOSURE,
  &&lbl_CLOSREC,
  &&lbl_DUMMY,
  &&lbl_UPDATE,
  &&lbl_PUSHTRAP,
  &&lbl_RAISE,
  &&lbl_POPTRAP,
  &&lbl_SWAP,
  &&lbl_PUSH,
  &&lbl_POP,
  &&lbl_ASSIGN,
  &&lbl_BOOLNOT,
  &&lbl_ADDINT,
  &&lbl_SUBINT,
  &&lbl_MULINT,
  &&lbl_DIVINT,
  &&lbl_MODINT,
  &&lbl_ANDINT,
  &&lbl_ORINT,
  &&lbl_XORINT,
  &&lbl_SHIFTLEFTINT,
  &&lbl_SHIFTRIGHTINTSIGNED,
  &&lbl_SHIFTRIGHTINTUNSIGNED,
  &&lbl_EQ,
  &&lbl_NEQ,
  &&lbl_LTINT,
  &&lbl_GTINT,
  &&lbl_LEINT,
  &&lbl_GEINT,
  &&lbl_FLOATOFINT,
  &&lbl_SMLNEGFLOAT,
  &&lbl_SMLADDFLOAT,
  &&lbl_SMLSUBFLOAT,
  &&lbl_SMLMULFLOAT,
  &&lbl_SMLDIVFLOAT,
  &&lbl_INTOFFLOAT,
  &&lbl_EQFLOAT,
  &&lbl_NEQFLOAT,
  &&lbl_LTFLOAT,
  &&lbl_GTFLOAT,
  &&lbl_LEFLOAT,
  &&lbl_GEFLOAT,
  &&lbl_STRINGLENGTH,
  &&lbl_GETSTRINGCHAR,
  &&lbl_SETSTRINGCHAR,
  &&lbl_EQSTRING,
  &&lbl_NEQSTRING,
  &&lbl_LTSTRING,
  &&lbl_GTSTRING,
  &&lbl_LESTRING,
  &&lbl_GESTRING,
  &&lbl_MAKEVECTOR,
  &&lbl_VECTLENGTH,
  &&lbl_GETVECTITEM,
  &&lbl_SETVECTITEM,
  &&lbl_SMLNEGINT,
  &&lbl_SMLSUCCINT,
  &&lbl_SMLPREDINT,
  &&lbl_SMLADDINT,
  &&lbl_SMLSUBINT,
  &&lbl_SMLMULINT,
  &&lbl_SMLDIVINT,
  &&lbl_SMLMODINT,
  &&lbl_MAKEREFVECTOR,
  &&lbl_SMLQUOTINT,
  &&lbl_SMLREMINT,
  &&lbl_CHECK_SIGNALS,
  &&lbl_STOP,
  &&lbl_EQUNSIGN,
  &&lbl_NEQUNSIGN,
  &&lbl_LTUNSIGN,
  &&lbl_GTUNSIGN,
  &&lbl_LEUNSIGN,
  &&lbl_GEUNSIGN
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT
, &&lbl_EVENT

@*2 Declarations for the registers of the abstract machine.
The most heavily used registers come first.
For reasonable performance, ``\texttt{pc}'' MUST reside in a register.
Many ``optimizing'' compilers underestimate the importance of ``\texttt{pc}'',
and don't put it in a register. 

For GCC users, I've hand-assigned registers for some architectures.

@<Declare register variables for the abstract machine@>=
#if defined(__GNUC__) && defined(sparc)
  register CODE @, pc @, asm("%l0");
  register value accu @, asm("%l1");
  register value * sp @, asm("%l2");

@ Motorolla 68k register variables.
@c
#elif defined(__GNUC__) && defined(mc68000)
  register CODE @, pc @, asm("a5");
  register value accu;
  register value * sp;

@ MIPS specific register variables.

@c
#elif defined(__GNUC__) && defined(mips)
  register CODE  @, pc @, @[asm("$20")@];
  register value  accu @, @[asm("$21")@];
  register value * sp @, @[asm("$22")@];

@ The ALPHA architecture register variables.
@c
#elif defined(__GNUC__) && defined(__alpha__)
  register CODE @,  pc @, @[asm("$11")@];
  register value  accu @, @[asm("$12")@];
  register value * sp @, @[asm("$13")@];

@ The HP/PA RISC register variables.

@c
#elif defined(__GNUC__) && defined(hppa)
  register CODE @,  pc @, @[asm("%r11")@];
  register value  accu @, @[asm("%r12")@];
  register value * sp @, @[asm("%r13")@];

@ The x86 register variables.
@c
#elif defined(__GNUC__) && defined(i386)
#if defined(MSDOS)
  register CODE @, pc @, @[asm("si")@];
  register value * sp @, @[asm("di")@];
#else
  register CODE @, pc @, @[asm("%esi")@];
  register value * sp @, @[asm("%edi")@];
#endif /* |MSDOS| */
  register value accu;

@ The ``default'' register assignment for everything else.
@c
#else 
  register CODE pc;
  register value accu;
  register value * sp;
#endif


@ @(interp.c@>=
#if defined(DIRECT_JUMP) && defined(THREADED)

  realcode_t realcode;

  switch (mode) {
  case 0:			// initialization
    raise_break_exn = 
      expandcode(byte_raise_break_exn, RAISE_CODE_LEN, jumptable);
    callback1_code = 
      expandcode(byte_callback1_code, CALLBACK_CODE_LEN, jumptable);
    callback2_code = 
      expandcode(byte_callback2_code, CALLBACK_CODE_LEN, jumptable);
    callback3_code = 
      expandcode(byte_callback3_code, CALLBACK_CODE_LEN, jumptable);
    return Atom(0);
  case 1:			// bytecode threading and execution
    realcode = expandcode(bprog, code_size, jumptable);
    if (rprog != NULL)
      *rprog = realcode;
    break;
  case 2:			// realcode execution, used by callback()
    realcode = *rprog;
    break;
  } 

/* To read immediate operands, read an entire word: */
#undef s16
#define s16(pc) (int)(*pc)
#define u8pc  (unsigned long)(*pc)
#define u8pci (unsigned long)(*pc++)
#define s16pc (long)(*pc)
#define u16pc (unsigned long)(*pc) 
#define s32pc (long)(*pc) 
#define u32pc (long)(*pc) 
#define SHORT 1
#define LONG  1
#define JUMPTGT(tgt) (realcode_t)tgt
#define JUMPSWITCHINDEX(pc, accu) (realcode_t)(*(pc + Long_val(accu)))

  pc = realcode;
#else

  switch (mode) {
  case 0:			// initialization
    raise_break_exn = byte_raise_break_exn;
    callback1_code = byte_callback1_code;
    callback2_code = byte_callback2_code;
    callback3_code = byte_callback3_code;
    return Atom(0);
  case 1:			// bytecode execution
    pc = bprog;
    break;
  case 2:			// bytecode execution, used by callback
    pc = *rprog;
    break;
  }

/* To read immediate operands, read some bytes after |pc|: */

#define SHORT  (sizeof(short))
#define LONG   (sizeof(int32))
#define DOUBLE (sizeof(double))

#define u8pc  (unsigned char)(*pc)
#define u8pci (unsigned char)(*pc++)
#define s16pc s16(pc)
#define u16pc u16(pc)
#define s32pc s32(pc)
#define u32pc u32(pc)
#define JUMPTGT(offset) (bytecode_t)(pc + offset)
#define JUMPSWITCHINDEX(pc, accu) (bytecode_t)(pc + s32(pc + 4 * Long_val(accu)))

#endif

  sp = extern_sp;
  extra_args = 0;
  env = null_env;
  accu = Val_long(0);
  initial_c_roots_head = c_roots_head;
  initial_sp_offset = stack_high - sp;
  initial_external_raise = external_raise;

  if (setjmp(raise_buf.buf)) {
    c_roots_head = initial_c_roots_head;
    accu = exn_bucket;
    goto raise_exception;
  }
  external_raise = &raise_buf;

#ifdef DEBUG
  log_ptr = log_buffer;
#endif

@ The |Next| macro handles going to the next instruction.

The |Instruct(name)| macro ``adds'' an opcode to the instruction
set. For compilers supporting computed |goto|s, this will produce a
label whose name is mangled from |name|. For all other compilers, this
will produce a |case| in a larger |switch| statement.

@(interp.c@>=
#ifdef DIRECT_JUMP
# define Instruct(name) @t\quad @> lbl_##name
# ifdef THREADED
#define Next @t\quad @> goto **pc++ 
# else
#  define Next @t\quad @> cur_instr = *pc++; goto *jumptable[cur_instr]
# endif
#else /* compiler lacks computed goto */
# define Instruct(name) @t\quad @> case name
# define Next @t\quad @> break
#endif

@
@(interp.c@>=
#ifdef DIRECT_JUMP
  Next;                         /* Jump to the first instruction */
#else
  while (1) {
#ifdef DEBUG
    if (icount-- == 0) stop_here ();
    *log_ptr++ = pc;
    if (log_ptr >= log_buffer + LOG_BUFFER_SIZE) log_ptr = log_buffer;
    disasm_instr(pc);
    Assert(sp >= stack_low);
    Assert(sp <= stack_high);
#endif /* |DEBUG| */
    cur_instr = *pc++;
  decode_instruction:
    switch (cur_instr) {
#endif /* |DIRECT_JUMP| */

@*1 Basic stack operations.

@(interp.c@>=
    Instruct(SWAP):  
    { value tmp = accu;
      accu = sp[0];
      sp[0] = tmp;
      Next;
    }
@ @(interp.c@>=
    Instruct(PUSH): 
    Instruct(PUSHACC0): *--sp = accu; Next;
@ @(interp.c@>=
    Instruct(ACC0): accu = sp[0]; Next;
@ @(interp.c@>=
    Instruct(PUSHACC1): *--sp = accu; /* Fallthrough */
    Instruct(ACC1): accu = sp[1]; Next;
@ @(interp.c@>=
    Instruct(PUSHACC2): *--sp = accu; /* Fallthrough */
    Instruct(ACC2): accu = sp[2]; Next;
@ @(interp.c@>=
    Instruct(PUSHACC3): *--sp = accu; /* Fallthrough */
    Instruct(ACC3): accu = sp[3]; Next;
@ @(interp.c@>=
    Instruct(PUSHACC4): *--sp = accu; /* Fallthrough */
    Instruct(ACC4): accu = sp[4]; Next;
@ @(interp.c@>=
    Instruct(PUSHACC5): *--sp = accu; /* Fallthrough */
    Instruct(ACC5): accu = sp[5]; Next;
@ @(interp.c@>=
    Instruct(PUSHACC6): *--sp = accu; /* Fallthrough */
    Instruct(ACC6): accu = sp[6]; Next;
@ @(interp.c@>=
    Instruct(PUSHACC7): *--sp = accu; /* Fallthrough */
    Instruct(ACC7): accu = sp[7]; Next;
@ @(interp.c@>=
    Instruct(PUSHACC): *--sp = accu; /* Fallthrough */
    Instruct(ACCESS): accu = sp[u16pc]; pc += SHORT; Next;
@ @(interp.c@>=
    Instruct(POP):
      sp += u16pc; pc += SHORT;
      Next;
@ @(interp.c@>=
    Instruct(ASSIGN):
      sp[u16pc] = accu; pc += SHORT;
      accu = Val_unit;
      Next;

@*2 Access in heap-allocated environment.

@(interp.c@>=
    Instruct(PUSHENV1): *--sp = accu; /* Fallthrough */
    Instruct(ENV1): accu = Field(env, 1); Next;
@ @(interp.c@>=
    Instruct(PUSHENV2): *--sp = accu; /* Fallthrough */
    Instruct(ENV2): accu = Field(env, 2); Next;
@ @(interp.c@>=
    Instruct(PUSHENV3): *--sp = accu; /* Fallthrough */
    Instruct(ENV3): accu = Field(env, 3); Next;
@ @(interp.c@>=
    Instruct(PUSHENV4): *--sp = accu; /* Fallthrough */
    Instruct(ENV4): accu = Field(env, 4); Next;
@ @(interp.c@>=
    Instruct(PUSHENV5): *--sp = accu; /* Fallthrough */
    Instruct(ENV5): accu = Field(env, 5); Next;
@ @(interp.c@>=
    Instruct(PUSHENV6): *--sp = accu; /* Fallthrough */
    Instruct(ENV6): accu = Field(env, 6); Next;
@ @(interp.c@>=
    Instruct(PUSHENV7): *--sp = accu; /* Fallthrough */
    Instruct(ENV7): accu = Field(env, 7); Next;
@ @(interp.c@>=
    Instruct(PUSHENVACC): *--sp = accu; /* Fallthrough */
    Instruct(ENVACC): accu = Field(env, u16pc); pc += SHORT; Next;
@ @(interp.c@>=
    Instruct(PUSH_ENV1_APPLY1): 
    { 
      sp -= 4;
      sp[0] = accu;
      sp[1] = (value)pc;
      sp[2] = env;
      sp[3] = Val_long(extra_args);
      extra_args = 0;
      accu = Field(env, 1); 
      goto apply;
    } 
@ @(interp.c@>=
    Instruct(PUSH_ENV1_APPLY2): 
    { value arg2 = sp[0];
      sp -= 4;
      sp[0] = accu;
      sp[1] = arg2;
      sp[2] = (value)pc;
      sp[3] = env;
      sp[4] = Val_long(extra_args);
      extra_args = 1;
      accu = Field(env, 1); 
      goto apply;
    } 
@ @(interp.c@>=
    Instruct(PUSH_ENV1_APPLY3): 
    { value arg2 = sp[0];
      value arg3 = sp[1];
      sp -= 4;
      sp[0] = accu;
      sp[1] = arg2;
      sp[2] = arg3;
      sp[3] = (value)pc;
      sp[4] = env;
      sp[5] = Val_long(extra_args);
      extra_args = 2;
      accu = Field(env, 1); 
      goto apply;
    } 
@ @(interp.c@>=
    Instruct(PUSH_ENV1_APPLY4): 
    { value arg2 = sp[0];
      value arg3 = sp[1];
      value arg4 = sp[2];
      sp -= 4;
      sp[0] = accu;
      sp[1] = arg2;
      sp[2] = arg3;
      sp[3] = arg4;
      sp[4] = (value)pc;
      sp[5] = env;
      sp[6] = Val_long(extra_args);
      extra_args = 3;
      accu = Field(env, 1); 
      goto apply;
    } 
@ @(interp.c@>=
    Instruct(PUSH_ENV1_APPTERM1):
    { sp = sp + u16pc - 2; pc += SHORT;
      
      sp[0] = accu;
    } /* Fall through */
    env1_appterm:
      accu = Field(env, 1); 
    appterm:
      pc = Code_val(accu);
      env = accu;
      goto check_signals;
@ @(interp.c@>=
    Instruct(PUSH_ENV1_APPTERM2):
    { value arg2 = sp[0];
      sp = sp + u16pc - 3; pc += SHORT;
      sp[0] = accu;
      sp[1] = arg2;
      extra_args += 1;
      goto env1_appterm;
    }
@ @(interp.c@>=
    Instruct(PUSH_ENV1_APPTERM3):
    { value arg2 = sp[0];
      value arg3 = sp[1];
      sp = sp + u16pc - 4; pc += SHORT;
      sp[0] = accu;
      sp[1] = arg2;
      sp[2] = arg3;
      extra_args += 2;
      goto env1_appterm;
    }
@ @(interp.c@>=
    Instruct(PUSH_ENV1_APPTERM4):
    { value arg2 = sp[0];
      value arg3 = sp[1];
      value arg4 = sp[2];
      sp = sp + u16pc - 5; pc += SHORT;
      sp[0] = accu;
      sp[1] = arg2;
      sp[2] = arg3;
      sp[3] = arg4;
      extra_args += 3;
      goto env1_appterm;
    }

@ Function application.

@(interp.c@>=
    Instruct(PUSH_RETADDR): {
      sp -= 3;
      sp[0] = (value) (JUMPTGT(s32pc));
      sp[1] = env;
      sp[2] = Val_long(extra_args);
      pc += LONG;
      Next;
    }
@ @(interp.c@>=
    Instruct(APPLY): {
      extra_args = u8pc - 1;
      goto apply;
    }
@ @(interp.c@>=
    Instruct(APPLY1): {
      value arg1 = sp[0];
      sp -= 3;
      sp[0] = arg1;
      sp[1] = (value)pc;
      sp[2] = env;
      sp[3] = Val_long(extra_args);
      extra_args = 0;
      goto apply;
    }
@ @(interp.c@>=
    Instruct(APPLY2): {
      value arg1 = sp[0];
      value arg2 = sp[1];
      sp -= 3;
      sp[0] = arg1;
      sp[1] = arg2;
      sp[2] = (value)pc;
      sp[3] = env;
      sp[4] = Val_long(extra_args);
      extra_args = 1;
      goto apply;
    }
@ @(interp.c@>=
    Instruct(APPLY3): {
      value arg1 = sp[0];
      value arg2 = sp[1];
      value arg3 = sp[2];
      sp -= 3;
      sp[0] = arg1;
      sp[1] = arg2;
      sp[2] = arg3;
      sp[3] = (value)pc;
      sp[4] = env;
      sp[5] = Val_long(extra_args);
      extra_args = 2;
      goto apply;
    }
@ @(interp.c@>=
    Instruct(APPLY4): {
      value arg1 = sp[0];
      value arg2 = sp[1];
      value arg3 = sp[2];
      value arg4 = sp[3];
      sp -= 3;
      sp[0] = arg1;
      sp[1] = arg2;
      sp[2] = arg3;
      sp[3] = arg4;
      sp[4] = (value)pc;
      sp[5] = env;
      sp[6] = Val_long(extra_args);
      extra_args = 3;
      goto apply;
    }
@ @(interp.c@>=
    Instruct(APPTERM): {
      int nargs = u8pci;
      int slotsize = u16pc; 
      value * newsp;
      int i;
      pc += SHORT;
      /* Slide the nargs bottom words of the current frame to the top
         of the frame, and discard the remainder of the frame */
      newsp = sp + slotsize - nargs;
      for (i = nargs - 1; i >= 0; i--) newsp[i] = sp[i];
      sp = newsp;
      extra_args += nargs - 1;
      goto appterm;
    }
@ @(interp.c@>=
    Instruct(APPTERM1): {
      value arg1 = sp[0];
      sp = sp + u16pc - 1; pc += SHORT;
      sp[0] = arg1;
      goto appterm;
    }
@ @(interp.c@>=
    Instruct(APPTERM2): {
      value arg1 = sp[0];
      value arg2 = sp[1];
      sp = sp + u16pc - 2; pc += SHORT;
      sp[0] = arg1;
      sp[1] = arg2;
      extra_args += 1;
      goto appterm;
    }
@ @(interp.c@>=
    Instruct(APPTERM3): {
      value arg1 = sp[0];
      value arg2 = sp[1];
      value arg3 = sp[2];
      sp = sp + u16pc - 3; pc += SHORT;
      sp[0] = arg1;
      sp[1] = arg2;
      sp[2] = arg3;
      extra_args += 2;
      goto appterm;
    }
@ @(interp.c@>=
    Instruct(APPTERM4): {
      value arg1 = sp[0];
      value arg2 = sp[1];
      value arg3 = sp[2];
      value arg4 = sp[3];
      sp = sp + u16pc - 4; pc += SHORT;
      sp[0] = arg1;
      sp[1] = arg2;
      sp[2] = arg3;
      sp[3] = arg4;
      extra_args += 3;
      goto appterm;
    }
@ @(interp.c@>=
    Instruct(RETURN1):
      sp += 1;
    return_code:
      if (extra_args > 0) {
        extra_args--;
        pc = Code_val(accu);
        env = accu;
      } else {
        pc = (CODE)(sp[0]);
        env = sp[1];
        extra_args = Long_val(sp[2]);
	sp += 3;
	if (something_to_do) goto process_signal; 
      }
      Next;
@ @(interp.c@>=
    Instruct(RETURN2):
      sp += 2;
      goto return_code;

@ @(interp.c@>=
    Instruct(RETURN):
      sp += u16pc; pc += SHORT;
      goto return_code;

@ @(interp.c@>=
    Instruct(RESTART): {
      int num_args = Wosize_val(env) - 2;
      int i;
      sp -= num_args;
      for (i = 0; i < num_args; i++) sp[i] = Field(env, i + 2);
      env = Field(env, 1);
      extra_args += num_args;
      Next;
    }

@
@(interp.c@>=
    Instruct(GRAB): {
      int required = u8pci;
      if (extra_args >= required) {
        extra_args -= required;
      } else {
        mlsize_t num_args, i;
        num_args = 1 + extra_args; /* arg1 + extra args */
        Alloc_small(accu, num_args + 2, Closure_tag);
        Field(accu, 1) = env;
        for (i = 0; i < num_args; i++) Field(accu, i + 2) = sp[i];
	/* Point to the preceding |RESTART| instruction.  This works in the 
	   bytecode as well as the threaded code; in both cases we have
	   three slots: |RESTART|, |GRAB|, |n|; and |pc| pointing past |n| now. */
        Code_val(accu) = pc - 3; 
        sp += num_args;
        pc = (CODE)(sp[0]);
        env = sp[1];
        extra_args = Long_val(sp[2]);
        sp += 3;
      }
      Next;
    }

@
@(interp.c@>=
    Instruct(CLOSURE): {
      int nvars = u8pci;
      int i;
      if (nvars > 0) *--sp = accu;
      Alloc_small(accu, 1 + nvars, Closure_tag);
      Code_val(accu) = JUMPTGT(s32pc);
      for (i = 0; i < nvars; i++) Field(accu, i + 1) = sp[i];
      sp += nvars;
      pc += LONG;
      Next;
    }

@
@(interp.c@>=
    Instruct(CLOSREC): {
      int nvars = u8pci;
      int i;
      if (nvars > 0) *--sp = accu;
      Alloc_small(accu, 2 + nvars, Closure_tag);
      Code_val(accu) = JUMPTGT(s32pc);
      Field(accu, 1) = Val_int(0);
      for (i = 0; i < nvars; i++) Field(accu, i + 2) = sp[i];
      sp += nvars;
      modify(&Field(accu, 1), accu);
      pc += LONG;
      Next;
    }

@ For recursive definitions.
@(interp.c@>=
    Instruct(DUMMY): {
      int size = u16pc + 1; /* |size + 1| to match |CLOSURE| */
      pc += SHORT;
      Alloc_small(accu, size, 0);
      while (size--) Field(accu, size) = Val_long(0);
      Next;
    }
@ @(interp.c@>=
    Instruct(UPDATE): {
      value newval = *sp++;
      mlsize_t size, n;
      size = Wosize_val(newval);
      Assert(size == Wosize_val(accu));
      Tag_val(accu) = Tag_val(newval);
      for (n = 0; n < size; n++) {
        modify(&Field(accu, n), Field(newval, n));
      }
      accu = Val_unit;
      Next;
    }

@*2 Globals.
@(interp.c@>=
    Instruct(PUSH_GETGLOBAL):
      *--sp = accu;
      /* Fallthrough */
    Instruct(GETGLOBAL):
      accu = Field(global_data, u32pc);
      pc += LONG;
      Next;

@ @(interp.c@>=
    Instruct(PUSH_GETGLOBAL_APPLY1): 
    { sp -= 4;
      sp[0] = accu;
      accu = Field(global_data, u32pc);
      pc += LONG;
      sp[1] = (value)pc;
      sp[2] = env;
      sp[3] = Val_long(extra_args);
      extra_args = 0;
    }
@ @(interp.c@>=
    apply:
      pc = Code_val(accu);
      env = accu;

      /* Fall through to 
         stack check: 
       */
      if (sp < stack_threshold) {
        extern_sp = sp;
        realloc_stack();
        sp = extern_sp;
      }

@ Fall though to signals check.
@(interp.c@>=
    check_signals:

    Instruct(CHECK_SIGNALS):    /* accu not preserved */
#ifdef PERIODIC_ACTION_FREQ
      { static int periodic_action_count = 1;
        if (--periodic_action_count == 0) {
          periodic_action_count = PERIODIC_ACTION_FREQ;
          ui_periodic_action();
        }
      }
#endif
#if defined(macintosh) && !defined(PERIODIC_ACTION_FREQ)
       ui_periodic_action();
#endif
#if ( defined(MSDOS) && defined(__GNUC__) ) || defined(WIN32)
      { static int poll_count = 1;
        if (--poll_count == 0) { poll_count = 500; poll_break(); }
      }
#endif
      if (something_to_do) goto process_signal;
      Next;

@
@(interp.c@>=
    Instruct(PUSH_GETGLOBAL_APPLY2): 
    { value arg2 = sp[0];
      sp -= 4;
      sp[0] = accu;
      sp[1] = arg2;
      accu = Field(global_data, u32pc);
      pc += LONG;
      sp[2] = (value)pc;
      sp[3] = env;
      sp[4] = Val_long(extra_args);
      extra_args = 1;
      goto apply;
    }
@
@(interp.c@>=
    Instruct(PUSH_GETGLOBAL_APPLY3): 
    { value arg2 = sp[0];
      value arg3 = sp[1];
      sp -= 4;
      sp[0] = accu;
      sp[1] = arg2;
      sp[2] = arg3;
      accu = Field(global_data, u32pc);
      pc += LONG;
      sp[3] = (value)pc;
      sp[4] = env;
      sp[5] = Val_long(extra_args);
      extra_args = 2;
      goto apply;
    }
@ @(interp.c@>=
    Instruct(PUSH_GETGLOBAL_APPLY4): 
    { value arg2 = sp[0];
      value arg3 = sp[1];
      value arg4 = sp[2];
      sp -= 4;
      sp[0] = accu;
      sp[1] = arg2;
      sp[2] = arg3;
      sp[3] = arg4;
      accu = Field(global_data, u32pc);
      pc += LONG;
      sp[4] = (value)pc;
      sp[5] = env;
      sp[6] = Val_long(extra_args);
      extra_args = 3;
      goto apply;
    }
@
@(interp.c@>=
    Instruct(PUSH_GETGLOBAL_APPTERM1):
      /* opcode, popnbr, globalindex */
      sp = sp + u16pc - 2; pc += SHORT;
      sp[0] = accu;
    getglobal_appterm:
      accu = Field(global_data, u32pc);
      pc = Code_val(accu);
      env = accu;
      goto check_signals;
    
@ @(interp.c@>=
    Instruct(PUSH_GETGLOBAL_APPTERM2):
    { value arg2 = sp[0];
      sp = sp + u16pc - 3; pc += SHORT;
      sp[0] = accu;
      sp[1] = arg2;
      extra_args += 1;
      goto getglobal_appterm;
    }

@ @(interp.c@>=
    Instruct(PUSH_GETGLOBAL_APPTERM3):
    { value arg2 = sp[0];
      value arg3 = sp[1];
      sp = sp + u16pc - 4; pc += SHORT;
      sp[0] = accu;
      sp[1] = arg2;
      sp[2] = arg3;
      extra_args += 2;
      goto getglobal_appterm;
    }

@ @(interp.c@>=
    Instruct(PUSH_GETGLOBAL_APPTERM4):
    { value arg2 = sp[0];
      value arg3 = sp[1];
      value arg4 = sp[2];
      sp = sp + u16pc - 5; pc += SHORT;
      sp[0] = accu;
      sp[1] = arg2;
      sp[2] = arg3;
      sp[3] = arg4;
      extra_args += 3;
      goto getglobal_appterm;
    }
@
@(interp.c@>=
    Instruct(SETGLOBAL):
      modify(&Field(global_data, u32pc), accu);
      accu = Val_unit; /* ? */
      pc += LONG;
      Next;

@*2 Allocation of blocks.

@(interp.c@>=
    Instruct(PUSHATOM0):
      *--sp = accu;
      /* Fallthrough */
    Instruct(ATOM0):
      accu = Atom(0); Next;

@ @(interp.c@>=
    Instruct(ATOM1):
      accu = Atom(1); Next;
    Instruct(ATOM2):
      accu = Atom(2); Next;
    Instruct(ATOM3):
      accu = Atom(3); Next;
    Instruct(ATOM4):
      accu = Atom(4); Next;
    Instruct(ATOM5):
      accu = Atom(5); Next;
    Instruct(ATOM6):
      accu = Atom(6); Next;
    Instruct(ATOM7):
      accu = Atom(7); Next;
    Instruct(ATOM8):
      accu = Atom(8); Next;
    Instruct(ATOM9):
      accu = Atom(9); Next;

    Instruct(PUSHATOM):
      *--sp = accu;
      /* Fallthrough */
    Instruct(ATOM):
      accu = Atom(u8pci); Next;

@
@(interp.c@>=
    Instruct(MAKEBLOCK):
      { header_t hdr;
        mlsize_t size;
	tag_t tag;
	int i;
	
	hdr = u32pc;
	pc += LONG;
	size = Wosize_hd(hdr);
	tag = Tag_hd(hdr);
        if (size < Max_young_wosize) {
          Alloc_small(tmp, size, tag);
          Field(tmp, size-1) = accu;
          for (i = size-2; i >= 0; i--) Field(tmp, i) = *sp++;
          accu = tmp;
        } else {
          Setup_for_gc;
          tmp = alloc_shr (size, tag);
          Restore_after_gc;
          initialize (&Field(tmp, size-1), accu);
          for (i = size-2; i >= 0; i--) initialize (&Field(tmp, i), *sp++);
          accu = tmp;
        }
	Next;
      }
@
@(interp.c@>=
    Instruct(MAKEBLOCK1): {
      tag_t tag = u8pci;
      value block;
      Alloc_small(block, 1, tag);
      Field(block, 0) = accu;
      accu = block;
      Next;
    }
@
@(interp.c@>=
    Instruct(MAKEBLOCK2): {
      tag_t tag = u8pci;
      value block;
      Alloc_small(block, 2, tag);
      Field(block, 0) = sp[0];
      Field(block, 1) = accu;
      sp += 1;
      accu = block;
      Next;
    }
@ @(interp.c@>=
    Instruct(MAKEBLOCK3): {
      tag_t tag = u8pci;
      value block;
      Alloc_small(block, 3, tag);
      Field(block, 0) = sp[1];
      Field(block, 1) = sp[0];
      Field(block, 2) = accu;
      sp += 2;
      accu = block;
      Next;
    }
@ @(interp.c@>=
    Instruct(MAKEBLOCK4): {
      tag_t tag = u8pci;
      value block;
      Alloc_small(block, 4, tag);
      Field(block, 0) = sp[2];
      Field(block, 1) = sp[1];
      Field(block, 2) = sp[0];
      Field(block, 3) = accu;
      sp += 3;
      accu = block;
      Next;
    }

@*2 Access to components of blocks.

@(interp.c@>=
    Instruct(GETFIELD0):
      accu = Field(accu, 0); Next;
    Instruct(GETFIELD1):
      accu = Field(accu, 1); Next;
    Instruct(GETFIELD2):
      accu = Field(accu, 2); Next;
    Instruct(GETFIELD3):
      accu = Field(accu, 3); Next;
    Instruct(GETFIELD):
      accu = Field(accu, u16pc); pc += SHORT; Next;

@ @(interp.c@>=
    Instruct(GETFIELD0_0):
      accu = Field(accu, 0); 
      accu = Field(accu, 0); 
      Next;

    Instruct(GETFIELD0_1):
      accu = Field(accu, 0); 
      accu = Field(accu, 1); 
      Next;

    Instruct(GETFIELD1_0):
      accu = Field(accu, 1); 
      accu = Field(accu, 0); 
      Next;

    Instruct(GETFIELD1_1):
      accu = Field(accu, 1); 
      accu = Field(accu, 1); 
      Next;

@ @(interp.c@>=
    Instruct(SETFIELD0):
      modify_dest = &Field(*sp++, 0);
      modify_newval = accu;
    modify:
      Modify(modify_dest, modify_newval);
      accu = Val_unit; /* Atom(0); */
      Next;
@ @(interp.c@>=
    Instruct(SETFIELD1):
      modify_dest = &Field(*sp++, 1);
      modify_newval = accu;
      goto modify;
@ @(interp.c@>=
    Instruct(SETFIELD2):
      modify_dest = &Field(*sp++, 2);
      modify_newval = accu;
      goto modify;
@ @(interp.c@>=
    Instruct(SETFIELD3):
      modify_dest = &Field(*sp++, 3);
      modify_newval = accu;
      goto modify;
@ @(interp.c@>=
    Instruct(SETFIELD):
      modify_dest = &Field(*sp++, u16pc);
      pc += SHORT;
      modify_newval = accu;
      goto modify;

@*2 Array operations.

@(interp.c@>=
    Instruct(VECTLENGTH):
      accu = Val_long(Wosize_val(accu));
      Next;
@ @(interp.c@>=
    Instruct(GETVECTITEM):
      accu = Field(sp[0], Long_val(accu));
      sp += 1;
      Next;
@ @(interp.c@>=
    Instruct(SETVECTITEM):
      modify_dest = &Field(sp[1], Long_val(sp[0]));
      modify_newval = accu;
      sp += 2;
      goto modify;

@*2 String operations.
@(interp.c@>=
    Instruct(GETSTRINGCHAR):
      accu = Val_int(Byte_u(sp[0], Long_val(accu)));
      sp += 1;
      Next;
@ @(interp.c@>=
    Instruct(SETSTRINGCHAR):
      Byte_u(sp[1], Long_val(sp[0])) = Int_val(accu);
      accu = Atom(0);
      sp += 2;
      Next;

@*2 Branches and conditional branches.
@(interp.c@>=
#define branch() pc = JUMPTGT(s32pc)

    Instruct(BRANCH):
      branch(); Next;
@ @(interp.c@>=
    Instruct(BRANCHIF):
      if (Tag_val(accu) != 0) branch(); else pc += LONG;
      Next;
@ @(interp.c@>=
    Instruct(BRANCHIFNOT):
      if (Tag_val(accu) == 0) branch(); else pc += LONG;
      Next;
@ @(interp.c@>=
    Instruct(POPBRANCHIFNOT):
      tmp = accu;
      accu = *sp++;
      if (Tag_val(tmp) == 0) branch(); else pc += LONG;
      Next;
@ @(interp.c@>=
    Instruct(BRANCHIFNEQTAG):
      if (Tag_val(accu) != u8pci) branch(); else pc += LONG;
      Next;
@ @(interp.c@>=
    Instruct(SWITCH):
      Assert(Long_val(accu) >= 0 && Long_val(accu) < *pc);
      pc++;
      pc = JUMPSWITCHINDEX(pc, accu);
      Next;
@ @(interp.c@>=
    Instruct(BOOLNOT):
      accu = Atom(Tag_val(accu) == 0); Next;
      

@*2 Exceptions.
@(interp.c@>=
    Instruct(PUSHTRAP):
      sp -= 4;
      Trap_pc(sp) = JUMPTGT(s32pc);
      Trap_link(sp) = trapsp;
      sp[2] = env;
      sp[3] = Val_long(extra_args);
      trapsp = sp;
      pc += LONG;
      Next;

@ @(interp.c@>=
    Instruct(POPTRAP):
      /* We should check here if a signal is pending, to preserve the
         semantics of the program w.r.t. exceptions. */
      /* Unfortunately,
         |process_signal| destroys the accumulator, and there is no
         convenient way to preserve it... */
      trapsp = Trap_link(sp);
      sp += 4;
      Next;

@ @(interp.c@>=
    raise_exception:			/* An external raise jumps here */

    Instruct(RAISE):            /* arg */
      sp = trapsp;
      if (sp >= stack_high - initial_sp_offset) {
        exn_bucket = accu;
        external_raise = initial_external_raise;
        longjmp(external_raise->buf, 1);
      }
      pc = Trap_pc(sp);
      trapsp = Trap_link(sp);
      env = sp[2];
      extra_args = Long_val(sp[3]);
      sp += 4;
      Next;
@
@(interp.c@>=
    process_signal:
      something_to_do = 0;
      if (force_minor_flag){
	force_minor_flag = 0;
	Setup_for_gc;
	minor_collection ();
	Restore_after_gc;
      }
      /* If a signal arrives between the following two instructions,
         it will be lost. */
      { int signal_number = signal_is_pending;
        signal_is_pending = 0;
        if (signal_number) {
          /* Push a return frame to the current code location */
          sp -= 4;
          sp[0] = Val_int(signal_number);
          sp[1] = (value) pc;
          sp[2] = env;
          sp[3] = Val_long(extra_args);
          /* Branch to the signal handler */
          /* e -- |signal_handler| should be a closure, but isn't in 1.31.
          |env = (value )signal_handler;|
          |pc = Code_val(env);|
          I'm lazy, so for now... */
          env = null_env;
          pc = signal_handler;
          extra_args = 0;
        }
      }
      Next;

@*2 Calling C functions.
@(interp.c@>=
    Instruct(C_CALL1):
      Setup_for_c_call;
      accu = (cprim[u16pc])(accu);
      Restore_after_c_call;
      pc += SHORT;
      Next;
@ @(interp.c@>=
    Instruct(C_CALL2):
      Setup_for_c_call;
      /* |sp[0]| temporarily holds the environment pointer */
      accu = (cprim[u16pc])(sp[1], accu);
      Restore_after_c_call;
      pc += SHORT;
      sp += 1;
      Next;
@ @(interp.c@>=
    Instruct(C_CALL3):
      Setup_for_c_call;
      accu = (cprim[u16pc])(sp[2], sp[1], accu);
      Restore_after_c_call;
      pc += SHORT;
      sp += 2;
      Next;
@ @(interp.c@>=
    Instruct(C_CALL4):
      Setup_for_c_call;
      accu = (cprim[u16pc])(sp[3], sp[2], sp[1], accu);
      Restore_after_c_call;
      pc += SHORT;
      sp += 3;
      Next;
@ @(interp.c@>=
    Instruct(C_CALL5):
      Setup_for_c_call;
      accu = (cprim[u16pc])(sp[4], sp[3], sp[2], sp[1], accu);
      Restore_after_c_call;
      pc += SHORT;
      sp += 4;
      Next;
@ @(interp.c@>=
    Instruct(C_CALLN):
      { int n = u8pci;
        value * args;
	int i;
        *--sp = accu;
        Setup_for_c_call;
	args = (value*)malloc(n * sizeof(value));
	for (i = 0; i < n; i++) 
	  args[i] = sp[n-i];
        accu = (cprim[u16pc])(args, n);
        Restore_after_c_call;
        pc += SHORT;
	free(args);
        sp += n;
        Next; }
@*2 Small values.
@(interp.c@>=
    Instruct(CONSTBYTE): accu = u8pci;  Next;

    Instruct(CONSTSHORT): accu = s16pc; pc += SHORT; Next;

@*2 Integer constants.
@(interp.c@>=
    Instruct(PUSHCONST0): *--sp = accu; /* Fallthrough */
    Instruct(CONST0): accu = Val_int(0); Next;

@ @(interp.c@>=
    Instruct(PUSHCONST1): *--sp = accu; /* Fallthrough */
    Instruct(CONST1): accu = Val_int(1); Next;

@ @(interp.c@>=
    Instruct(PUSHCONST2): *--sp = accu; /* Fallthrough */
    Instruct(CONST2): accu = Val_int(2); Next;

@ @(interp.c@>=
    Instruct(PUSHCONST3): *--sp = accu; /* Fallthrough */
    Instruct(CONST3): accu = Val_int(3); Next;

@ @(interp.c@>=
    Instruct(PUSHCONSTINT): *--sp = accu; /* Fallthrough */
    Instruct(CONSTINT):
      accu = Val_int(s32pc);
      pc += LONG;
      Next;

@*2 Unsigned integer arithmetic modulo |2^(wordsize-1)|.
@(interp.c@>=
    Instruct(ADDINT):		/* Modified for Moscow ML: unsigned */
      accu = (unsigned long) ((unsigned long) *sp++ 
			      + (unsigned long) (accu - 1)); Next;
@ @(interp.c@>=
    Instruct(SUBINT):		/* unsigned */
      accu = (unsigned long) ((unsigned long) *sp++ 
			      - (unsigned long) (accu - 1)); Next;
@ @(interp.c@>=
    Instruct(MULINT):		/* unsigned */
      accu = (unsigned long) (1 + (unsigned long) (*sp++ >> 1) 
			      * (unsigned long) (accu - 1)); Next;
@ @(interp.c@>=
    Instruct(DIVINT):		/* unsigned */
      tmp = accu - 1;
      if (tmp == 0) {
        accu = Field(global_data, EXN_DIV);
        goto raise_exception;
      }
      accu = Val_long((unsigned long) ((unsigned long) (*sp++ - 1) 
				       / (unsigned long) tmp));
      Next;
@
@(interp.c@>=
    Instruct(MODINT):
      tmp = accu - 1;
      if (tmp == 0) {
        accu = Field(global_data, EXN_DIV);
        goto raise_exception;
      }
      accu = (unsigned long) (1 + (unsigned long) (*sp++ - 1) 
			      % (unsigned long) tmp);
      Next;
@
@(interp.c@>=
    Instruct(ANDINT):
      accu &= *sp++; Next;
    Instruct(ORINT):
      accu |= *sp++; Next;
    Instruct(XORINT):
      accu = 1 + (accu ^ *sp++); Next;
    Instruct(SHIFTLEFTINT):
      accu = 1 + ((*sp++ - 1) << Long_val(accu)); Next;
    Instruct(SHIFTRIGHTINTSIGNED):
      accu = 1 | ((*sp++ - 1) >> Long_val(accu)); Next;
    Instruct(SHIFTRIGHTINTUNSIGNED):
      accu = 1 | ((unsigned long)(*sp++ - 1) >> Long_val(accu)); Next;

@
@(interp.c@>=
#define inttest(name1,name2,tst)					     \
    Instruct(name1):							     \
      accu = Atom(*sp++ tst accu);					     \
      Next;								     \
    Instruct(name2):							     \
      if (*sp++ tst accu) { branch(); } else { pc += LONG; }                 \
      Next;
      
      inttest(EQ,BRANCHIFEQ,==);
      inttest(NEQ,BRANCHIFNEQ,!=);
      inttest(LTINT,BRANCHIFLT,<);
      inttest(GTINT,BRANCHIFGT,>);
      inttest(LEINT,BRANCHIFLE,<=);
      inttest(GEINT,BRANCHIFGE,>=);

    Instruct(TAGOF):
      accu = Val_long(Tag_val(accu));
      Next;

@
@(interp.c@>=
#define unsigntest(name, tst)    					\
    Instruct(name):							\
      accu = Atom((unsigned long)(*sp++) tst (unsigned long)accu);	\
      Next;								\

      unsigntest(EQUNSIGN,==);
      unsigntest(NEQUNSIGN,!=);
      unsigntest(LTUNSIGN,<);
      unsigntest(GTUNSIGN,>);
      unsigntest(LEUNSIGN,<=);
      unsigntest(GEUNSIGN,>=);

@ @(interp.c@>=
    Instruct(BRANCHINTERVAL):
      { value low_bound, high_bound;
        high_bound = accu;
        low_bound = *sp++;
        accu = *sp++;
        if (accu < low_bound) {
          branch();
          Next;
        }
        pc += LONG;
        if (accu > high_bound) {
          branch();
          Next;
        } 
        pc += LONG;
        accu = accu - low_bound + 1;
        Next;
      }

@*2 Moscow SML changes begin.
@(interp.c@>=
#define Check_float(dval) \
   if ((dval > maxdouble) || (dval < -maxdouble)) \
      { accu = Field(global_data, EXN_OVERFLOW); goto raise_exception; }

    Instruct(FLOATOFINT):
	dtmp = (double) Long_val(accu); goto float_done;

    Instruct(SMLNEGFLOAT):
	dtmp = -Double_val(accu);
	Check_float(dtmp); goto float_done;

    Instruct(SMLADDFLOAT):
	dtmp = Double_val(*sp++) + Double_val(accu);
	Check_float(dtmp); goto float_done;

    Instruct(SMLSUBFLOAT):
	dtmp = Double_val(*sp++) - Double_val(accu);
	Check_float(dtmp); goto float_done;

    Instruct(SMLMULFLOAT):
	dtmp = Double_val(*sp++) * Double_val(accu);
	Check_float(dtmp); goto float_done;

    Instruct(SMLDIVFLOAT):
	dtmp = Double_val(accu);
	if (dtmp == 0) {
	    accu = Field(global_data, EXN_DIV);
	    goto raise_exception;
	}
	dtmp = Double_val(*sp++) / dtmp;
	Check_float(dtmp); /* Fallthrough */
    float_done:
	Alloc_small(tmp, Double_wosize, Double_tag);
	Store_double_val(tmp, dtmp);
	accu = tmp;
	Next;

    /* --- Moscow SML changes end --- */
@*2 Floating-point comparison.
@(interp.c@>=
    Instruct(INTOFFLOAT):
      accu = Val_long((long)Double_val(accu)); Next;
      
#define floattest(name, tst)    					     \
    Instruct(name):							     \
      accu = Atom(Double_val(*sp++) tst Double_val(accu));		     \
      Next;
      
      floattest(EQFLOAT,==);
      floattest(NEQFLOAT,!=);
      floattest(LTFLOAT,<);
      floattest(GTFLOAT,>);
      floattest(LEFLOAT,<=);
      floattest(GEFLOAT,>=);
      
    Instruct(STRINGLENGTH):
      accu = Val_long(string_length(accu));
      Next;
@
@(interp.c@>=
#define stringtest(name, tst)                                                \
    Instruct(name):                                                          \
      accu = Atom(compare_strings(*sp++, accu) tst Val_long(0));             \
      Next;
      
      stringtest(EQSTRING,==);
      stringtest(NEQSTRING,!=);
      stringtest(LTSTRING,<);
      stringtest(GTSTRING,>);
      stringtest(LESTRING,<=);
      stringtest(GESTRING, >=);
@
@(interp.c@>=
    Instruct(MAKEVECTOR):
      { mlsize_t size = Long_val(sp[0]);
        /* Make sure that the object referred to by |sp[0]| survives gc: */
        sp[0] = accu;
        if (size == 0)
          accu = Atom(0);
        else if (size < Max_young_wosize){
	  Alloc_small (accu, size, 0);
	  do {size--; Field (accu, size) = *sp;} while (size != 0);
	}else if (Is_block (*sp) && Is_young (*sp)){
	  Setup_for_gc;
	  minor_collection ();
	  tmp = alloc_shr (size, 0);
	  Restore_after_gc;
          accu = tmp;
	  do {size--; Field (accu, size) = *sp;} while (size != 0);
	}else{
	  Setup_for_gc;
	  tmp = alloc_shr (size, 0);
	  Restore_after_gc;
          accu = tmp;
	  do {size--; initialize(&Field(accu, size), *sp);} while (size != 0);
	}
	sp++;
	Next;
      }

@*2 Additional instructions for Moscow SML.
@(interp.c@>=
    Instruct(SMLNEGINT):
      tmp =  - Long_val(accu);
      accu = Val_long(tmp);
      if( Long_val(accu) != tmp ) 
	goto raise_overflow;
      Next;
    raise_overflow:
      accu = Field(global_data, EXN_OVERFLOW);
      goto raise_exception;

    Instruct(SMLSUCCINT):
      tmp =  Long_val(accu) + 1;
      accu = Val_long(tmp);
      if( Long_val(accu) != tmp ) 
	goto raise_overflow;
      Next;
    Instruct(SMLPREDINT):
      tmp =  Long_val(accu) - 1;
      accu = Val_long(tmp);
      if( Long_val(accu) != tmp ) 
        goto raise_overflow;
      Next;
    Instruct(SMLADDINT):
      tmp = Long_val(*sp++) + Long_val(accu);
      accu = Val_long(tmp);
      if( Long_val(accu) != tmp ) 
	goto raise_overflow;
      Next;
    Instruct(SMLSUBINT):
      tmp = Long_val(*sp++) - Long_val(accu);
      accu = Val_long(tmp);
      if( Long_val(accu) != tmp ) 
	goto raise_overflow;
      Next;
@
@(interp.c@>=
#define ChunkLen (4 * sizeof(value) - 1)
#define MaxChunk ((1L << ChunkLen) - 1)

    Instruct(SMLMULINT):
      { register long x, y;
        register int isNegative = 0;
        x = Long_val(*sp++);
        y = Long_val(accu);
        if( x < 0 ) { x = -x; isNegative = 1; }
        if( y < 0 ) { y = -y; isNegative = !isNegative; }
        if( y > x ) { tmp = y; y = x; x = tmp; }
        if( y > MaxChunk ) 
	  goto raise_overflow;
        if( x <= MaxChunk )
          { accu = Val_long(isNegative?(-(x * y)):(x * y)); }
        else /* |x > MaxChunk| */
          { tmp = (x >> ChunkLen) * y;
            if( tmp > MaxChunk + 1) 
	      goto raise_overflow;
            tmp = (tmp << ChunkLen) + (x & MaxChunk) * y;
            if( isNegative ) tmp = - tmp;
            accu = Val_long(tmp);
            if( Long_val(accu) != tmp ) 
	      goto raise_overflow;
          }
      }
      Next;
@
@(interp.c@>=
    Instruct(SMLDIVINT):
      tmp = Long_val(accu);
      accu = Long_val(*sp++);
      if (tmp == 0) 
	{ accu = Field(global_data, EXN_DIV);
	  goto raise_exception;
	}
      if( tmp < 0 ) { accu = - accu; tmp = -tmp; }
      if( accu >= 0 )
        { tmp = accu / tmp; }
      else
        { accu = - accu;
          if( accu % tmp == 0 )
            tmp = - (accu /tmp);
          else
            tmp = - (accu / tmp) - 1;
        }
      accu = Val_long(tmp);
      if( Long_val(accu) != tmp ) 
	goto raise_overflow;
      Next;
@
@(interp.c@>=
    Instruct(SMLMODINT):
      { register long y;
      y = tmp = Long_val(accu);
      accu = Long_val(*sp++);
      if (tmp == 0) 
	{ accu = Field(global_data, EXN_DIV);
	  goto raise_exception;
	}
      if( tmp < 0 ) { accu = -accu; tmp = -tmp; }
      if( accu >= 0 )
        tmp = accu % tmp;
      else
        { accu = (-accu) % tmp;
          tmp = ( accu == 0 )?( 0 ):( tmp - accu );
        }
      if( y < 0 ) tmp = -tmp;
      accu = Val_long(tmp);
      if( Long_val(accu) != tmp ) 
	goto raise_overflow;
      }
      Next;
@
@(interp.c@>=
    Instruct(MAKEREFVECTOR):
      { mlsize_t size = Long_val(sp[0]);
        sp[0] = accu;
        if (size == 0)
          accu = Atom(Reference_tag);
        else if (size < Max_young_wosize){
          Alloc_small (accu, size, Reference_tag);
	  do {size--; Field (accu, size) = *sp;} while (size != 0);
	}else if (Is_block (*sp) && Is_young (*sp)){
	  Setup_for_gc;
	  minor_collection ();
          tmp = alloc_shr (size, Reference_tag);
	  Restore_after_gc;
          accu = tmp;
	  do {size--; Field (accu, size) = *sp;} while (size != 0);
	}else{
	  Setup_for_gc;
          tmp = alloc_shr (size, Reference_tag);
	  Restore_after_gc;
          accu = tmp;
	  do {size--; initialize(&Field(accu, size), *sp);} while (size != 0);
	}
	sp++;
	Next;
      }
@
@(interp.c@>=
    Instruct(SMLQUOTINT):
      tmp = accu - 1;
      if (tmp == 0) 
	{ accu = Field(global_data, EXN_DIV);
	  goto raise_exception;
	}
      tmp = (*sp++ - 1) / tmp;
      accu = Val_long(tmp);
      if( Long_val(accu) != tmp ) 
	goto raise_overflow;
      Next;
    Instruct(SMLREMINT):
      tmp = accu - 1;
      if (tmp == 0) {
        accu = Field(global_data, EXN_DIV);
        goto raise_exception;
      }
      accu = 1 + (*sp++ - 1) % tmp;
      Next;

/* --- End of additional instructions for Moscow SML --- */

@*2 Machine control.
@(interp.c@>=
    Instruct(STOP):
      extern_sp = sp;
      external_raise = initial_external_raise;
      return accu;
      
#ifdef DIRECT_JUMP
    lbl_EVENT:
#else
    default:
#endif

      fatal_error("bad opcode");
      return Val_unit;		/* Can't reach the return */

#ifndef DIRECT_JUMP
    }
  }
#endif
}

@
@(interp.c@>=
EXTERN value callback(value closure, value arg)
{
  value res;
  extern_sp -= 2;
  extern_sp[0] = arg;
  extern_sp[1] = closure;
  /* |callback_depth++;| */
  res = interprete(/* mode=exec */ 2, NULL, 0, &callback1_code);
  /* |callback_depth--;| */
  return res;
}
@
@(interp.c@>=
EXTERN value callback2(value closure, value arg1, value arg2)
{
  value res;
  extern_sp -= 3;
  extern_sp[0] = arg1;
  extern_sp[1] = arg2;
  extern_sp[2] = closure;
  /* |callback_depth++;| */
  res = interprete(/* mode=exec */ 2, NULL, 0, &callback2_code);
  /* |callback_depth--;| */
  return res;
}
@
@(interp.c@>=
EXTERN value callback3(value closure, value arg1, value arg2, value arg3)
{
  value res;
  extern_sp -= 4;
  extern_sp[0] = arg1;
  extern_sp[1] = arg2;
  extern_sp[2] = arg3;
  extern_sp[3] = closure;
  /* |callback_depth++;| */
  res = interprete(/* mode=exec */ 2, NULL, 0, &callback3_code);
  /* |callback_depth--;| */
  return res;
}



