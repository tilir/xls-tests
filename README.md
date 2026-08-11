# XLS experiments

Each experiment has its own subdirectory and `CMakeLists.txt`. Register a new
experiment explicitly with `add_subdirectory(name)` in the root
`CMakeLists.txt`. Generated IR and SystemVerilog are written to the build tree.

Configure and build everything:

```sh
cmake -S . -B build -DXLS_ROOT=/path/to/xls
cmake --build build
```

Build only the CRC entry point:

```sh
cmake --build build --target crc16
```

To add an entry point (including another one in the same experiment), add this
to that experiment's `CMakeLists.txt`:

```cmake
xls_add_dslx(target_name
  SOURCE source_file.x
  TOP DslxTopName
  OUTPUT_NAME generated_file_stem)
```

All `.x` files beside `SOURCE` are dependencies. Thus helper/imported DSLX
files cause a rebuild, but are not assumed to be independently synthesizable.
Extra code generator flags can be passed with `CODEGEN_ARGS`.
