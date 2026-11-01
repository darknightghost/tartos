===
dsl
===

The ``dsl/`` directory hosts the DSL that describes the driver-IPC
interface.  This document is the reference for its syntax.

Purpose
=======

A DSL description is compiled into **C++ and Rust** source files.  The
generated content is limited to compile-time constants and data-structure
definitions: no executable logic is expressed in the DSL.

Source files
============

DSL description files carry the ``.tiface`` extension.

Package
-------

A package is declared once per directory::

    package a.b.c;

* The declaration applies to **every file in the same directory**; the
  package statement inside any single file therefore defines the package of
  the whole directory.
* Files in a subdirectory ``d/`` of that directory belong to
  ``a.b.c.d``: the subdirectory name is appended to the parent package.

Comments
--------

Comments follow the Doxygen C++ comment rules required by the repository
``AGENTS.md``: ``/** ... */`` blocks with aligned ``@brief`` / ``@param`` /
``@return`` / ``@note`` tags separated by blank comment lines, ``///``
single-line comments, and ``///<`` trailing member comments.

Declarations
============

Naming follows the repository conventions (``AGENTS.md``): types are
``UpperCamelCase``, fields and parameters are ``snake_case``, constants are
``SCREAMING_SNAKE_CASE``.

Basic types
-----------

================================================ ==============================
Kind                                             Types
================================================ ==============================
Fixed-width unsigned integers                    ``U8``, ``U16``, ``U32``, ``U64``
Fixed-width signed integers                      ``S8``, ``S16``, ``S32``, ``S64``
Word-sized integers (same as C++ concepts)       ``Size`` (unsigned), ``SSize`` (signed)
Pointer-sized integers                           ``IntPtr``, ``UIntPtr``
String                                           ``String``
Ownership wrappers                               ``Unique<T>``, ``Shared<T>``
================================================ ==============================

``String`` is a struct-like type laid out as a ``Size`` member ``size``
followed by an ``S8`` array of ``size`` elements.

``Unique<T>`` and ``Shared<T>`` are the DSL spelling of the two owning
wrapper types, matching ``Box<T>`` and ``Arc<T>`` in Rust (single
ownership and reference-counted shared ownership); a bare ``T*`` stays a
borrow.  See “Resource ownership” in ``doc/kernel-design.rst``.

Type qualifiers
---------------

Any type may carry ``const``, ``volatile`` and pointer (``*``) qualifiers,
with the same semantics as C++, e.g. ``const void*``, ``volatile U32*``.

A pointer or reference in a ``.tiface`` interface **denotes a borrow**
(ownership convention in ``AGENTS.md`` / “Resource ownership” in
``doc/kernel-design.rst``): the receiving side may read or write through
it only for the duration of the call, and may neither keep it nor free
what it points to.  ``write(data : const void*, size : Size) -> SSize;``
therefore means “borrowed, read-only payload of ``size`` bytes (B)”.
Ownership that does travel through an interface is written with the
``Unique`` / ``Shared`` wrapper types listed under “Basic types”.

flag
----

A named set of constants, equivalent to C++ ``enum class``::

    /**
      * @brief   Open mode
      */
    flag OpenMode: U32 {
        Read      = 0x0000001, ///< Open for read.
        Write     = 0x00000002, ///< Open for write.
        Binary    = 4, ///< Open as binary file.
        ReadWrite = Read | Write ///< Open for read and write.
    };

* ``flag <Name>: <basic integer type> { ... }`` — the ``:`` part declares
  the underlying type.
* Member values are C++ constant expressions (see “Constants” below) and
  may reference previously defined members with ``|`` combinations.

flags
-----

The result type of flag bit operations, bound to one ``flag`` type::

    /// Open modes.
    flags OpenModes<OpenMode>;

In generated C++ this is a struct with a single ``value`` member whose type
is the underlying type of the referenced flag.

struct
------

A POD data structure::

    /**
      * @brief   Child struct.
      */
    struct Child : Parent implements IOpen {
        open_mode: OpenModes; ///< Open modes.
        size     : Size;      ///< File size.
    };

* Fields are declared ``name: Type;``.
* **Single inheritance only.**  A ``: Parent`` base clause is compiled to a
  first member named ``base`` of the base-struct type; the remaining fields
  follow it, reproducing C++ standard-layout inheritance.
* An optional ``implements`` clause lists the interfaces whose callbacks
  this struct provides.

callback
--------

A function-pointer signature, declarable as a named type::

    /**
      * @brief      Open callback.
      *
      * @param[in]  path   Path.
      * @param[in]  mode   Mode.
      *
      * @return     Fd, or -1 on error.
      */
    callback OpenCallback(path : String, mode : OpenModes) -> S32;

A ``callback`` type may be used anywhere a value type can: as a callback
parameter, as a return type, and as a struct member — it always denotes a
function pointer.

iface
-----

An interface: a vtable attached out-of-line to a struct (the struct holds
no vtable pointer itself).  Interfaces support combining through multiple
inheritance::

    /**
      * @brief   Open interface.
      */
    iface IOpen : ISuper1, ISuper2 {
        open: OpenCallback; ///< Open file.
        /**
          * @brief      Write data.
          *
          * @param[in]  data    Data to write.
          * @param[in]  size    Size to write.
          *
          * @return     Size written.
          */
        write(data : const void*, size : Size) -> SSize;
    };

* Members are either a reference to a declared ``callback`` type
  (``open: OpenCallback;``) or an inline method signature
  (``write(...) -> SSize;``); both compile to one vtable entry.
* ``iface X : A, B { ... }`` composes the vtables of ``A`` and ``B``.

DynIface
--------

A special generic type ``DynIface<DataType, Interface>``: an interface
reference bound to one concrete data type — analogous to Rust ``dyn Trait``
with a known underlying object type.  Its layout is fixed:

#. first field ``data``: pointer to ``DataType``;
#. second field ``interface``: pointer to the vtable of ``Interface``.

Constants
---------

Compile-time constants use ``NAME : Type = expression;``::

    CONSTANT_INT1   : U32   = 10 + 10;
    CONSTANT_INT2   : U32   = 1 == 1 ? 2 : 3;
    CONSTANT_STRUCT : Child = Child {
                          .base = Parent{
                              .a = 1
                          },
                          .open_mode = OpenMode::Read | OpenMode::Write,
                          .size = 10
                      };

* Values are C++ constant expressions: every operator valid in a C++
  constant expression is supported (arithmetic, comparison, ``?:``, bit
  operations, ...).  Operators that cannot appear in a constant expression
  (``++``, ``--``, ``+=`` and friends) are rejected.
* Struct constants use designated-initializer syntax ``.field = value``.
  With inheritance the base struct is initialized through the ``.base``
  field.  Flag members are referenced as ``OpenMode::Read`` and combined
  with ``|``.
