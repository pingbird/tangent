![](https://i.tst.sh/9gQQ5.png)

### Tangent - A discord bot with a full Linux VM

### https://discord.gg/F2F2EdE

## How it works
Tangent uses [libvirt](https://libvirt.org/) to manage a qemu controlled Debian 9 virtual machine and communicates to it through a custom json rpc like protocol.

`tangent-server` contains the server that runs as an unprivelaged user on the VM, allowing the bot on the host machine to start processes, read stdin/stdout, and access files safely.

In it's current configuration the VM is on a closed virtual network with only the host machine being routable (`192.168.69.1`), iptables are set up so requests from the VM to the host are blocked to prevent it from attempting to connect to SSH or other services it should not have access to.

The only way for information to go in and out of the VM is through connections initiated by the host.

System resources are also heavily limited with 1 thread, 256MB of memory, and a 16GB virtual disk.

If you manage to put the VM in an unusable state for example by killing the server process, Tangent will automatically use virsh to reboot the VM which only takes around 4 seconds.

As a last resort if someone obtains root and bricks the system a qcow2 snapshot can restore the system state to brand new using the `qclean` command.

The bot itself is a Dart application and is designed to be as fault tolerant as possible, all buffers that the vm send to are capped, any malformed packets will instantly terminate the connection, and all of the async wrappers for files and processes are destroyed properly when closed.

## Usage

### Prefixes
Currently there are 3 command prefixes for convenience:
`.`, `α`, `@Tangent` (Will have per-server configuration later)

Any of these prefixes can be used to execute commands

### Misc commands
`purge <n>` - Purges a number of messages [admin only]

### Managment
`qstart` - Start the VM *[trusted only]*\
`qrestart` - Restart the VM *[trusted only]*\
`qclean` - Revert the VM state to a clean snapshot *[trusted only]*

### Upload / Download
`upload [file/dir]` - Upload an attachment to the VM at the specified directory or file name, defaults to the home directory\
`download <file>` - Download a specific file from the VM to Discord

### Languages
Language commands support discord's code block formatting, for example:
````
lua ```lua
print("Hello, World!")
```
````
will interpret the contents of the code block.

You can provide compiler arguments and program arguments by putting text before and after the code block:
````
.c -ldl ```c
#include <stdio.h>
int main(int argc, char** argv) {
    printf("Hello\n");
    for (int i = 0; i < argc; i++) {
        printf("%i: %s\n", i, argv[i]);
    }
}
```
extra arguments
````
Outputs:
```
Hello
0: ./tangent
1: extra
2: arguments
```

The bot is interactive, if you edit your message with a command it will re-run your command and update it's message.
When a user enters a new command or edit a previous one it will kill the previous process to prevent anything from lingering.

#### Commands:

`sh <code>` - Standard /bin/sh
<details>
<summary>Example</summary>

```sh
echo Hello from /bin/sh
```
</details>

`bash <code>` - Standard /bin/bash
<details>
<summary>Example</summary>

```sh
echo Hello from /bin/bash
```
</details>

`arm <code>` - ARM Assembly
<details>
<summary>Example</summary>

```arm
.globl main
main:
    stmfd sp!, {lr}
    ldr r0, =hello_text
    bl puts
    mov r0, #0
    ldmfd sp!, {lr}
    bx lr
hello_text:
    .string "Hello from ARM\n"
```
</details>

`x86 <code>` - x86_64 Assembly
<details>
<summary>Example</summary>

```asm
.intel_syntax noprefix
.globl main
main:
    push rax
    mov edi, offset hello_text
    xor eax, eax
    call puts
    xor eax, eax
    pop rcx
    ret
hello_text:
    .string "Hello from x86\n"
```
</details>

`c <code>` - GCC 6.3.0
<details>
<summary>Example</summary>

```c
#include <stdio.h>
int main() {
    puts("Hello from C\n");
}
```
</details>

`cpp <code>` - G++ 6.3.0
<details>
<summary>Example</summary>

```cpp
#include <iostream>
int main() {
    std::cout << "Hello from C++\n";
}
```
</details>

`lua <code>` - Lua 5.3 Reference interpreter
<details>
<summary>Example</summary>

```lua
print("Hello from " .. _VERSION)
```
</details>

`lua5.2 <code>` - Lua 5.2 Reference interpreter
<details>
<summary>Example</summary>

```lua
print("Hello from " .. _VERSION)
```
</details>

`lua5.1 <code>` - Lua 5.1 Reference interpreter
<details>
<summary>Example</summary>

```lua
print("Hello from " .. _VERSION)
```
</details>

`luajit <code>` - LuaJIT 2.0
<details>
<summary>Example</summary>

```lua
print("Hello from " .. _VERSION)
```
</details>

`py <code>` - Python 3
<details>
<summary>Example</summary>

```py
from platform import python_version
print('Hello from Python {}'.format(python_version()))
```
</details>

`py2 <code>` - Python 2
<details>
<summary>Example</summary>

```py
from platform import python_version
print('Hello from Python {}'.format(python_version()))
```
</details>

`js <code>` - Node.JS v4.8.2
<details>
<summary>Example</summary>

```js
console.log("Hello from Node.js " + process.version);
```
</details>

`pl <code>` - Perl 
<details>
<summary>Example</summary>

```pl
print "Hello from Perl\n";
```
</details>

`java <code>` - OpenJDK 8
<details>
<summary>Example</summary>

```java
public class Tangent {
    public static void main(String[] args) {
        System.out.println("Hello from Java");
    }
}
```
</details>

`lisp <code>` - SBCL
<details>
<summary>Example</summary>

```lisp
(format t "Hello from Lisp")```

</details>

`bf <code>` - Brainfuck
<details>
<summary>Example</summary>

```bf
++++++++++[>+>+++>+++++++>++++++++++<<<<-]>>>++.>+.+++++++..+++.<<++.>>---------.++++++++++++.---.--.<<.>------.>+++++.-----------------.++++++++.+++++.--------.+++++++++++++++.------------------.++++++++.
```
</details>

`cs <code>` - .NET Core C#
<details>
<summary>Example</summary>

```cs
class Program {
    static void Main() {
        System.Console.WriteLine("Hello from C#");
    }
}
```
</details>

`fs <code>` - .NET Core F#
<details>
<summary>Example</summary>

```fs
[<EntryPoint>]
let main argv =
    printfn "Hello from F#"
    0
```
</details>

`haskell <code>` - GHC
<details>
<summary>Example</summary>

```hs
main = putStrLn "Hello from Haskell"
```
</details>

`php <code>` - PHP7
<details>
<summary>Example</summary>

```php
<?php
echo('Hello from PHP');
```
</details>

`cobol <code>` - OpenCOBOL
<details>
<summary>Example</summary>

```cob
PROGRAM-ID. HELLO.
PROCEDURE DIVISION.
    DISPLAY 'Hello from COBOL'.
    STOP RUN.
```
</details>

`go <code>` - Go 1.7.4
<details>
<summary>Example</summary>

```go
package main
import "fmt"
func main() {
    fmt.Println("Hello from Go")
}
```
</details>

`ruby <code>` - Ruby 2.3.3
<details>
<summary>Example</summary>

```rb
puts 'Hello from Ruby'
```
</details>

`apl <code>` - GNU APL
<details>
<summary>Example</summary>

```apl
"Hello from APL"
```
</details>

`prolog <code>` - SWI Prolog
<details>
<summary>Example</summary>

```pl
:- initialization hello, halt.
hello :-
    write('Hello from Prolog'), nl.
```
</details>

`ocaml <code>` - OCaml 4.02.3
<details>
<summary>Example</summary>

```ml
print_string "Hello from OCaml\n";;
```
</details>

`sml <code>` - SML-NJ v110.79
<details>
<summary>Example</summary>

```sml
print "Hello from SML\n";
```
</details>

`crystal <code>` - Crystal 0.28.0
<details>
<summary>Example</summary>

```cr
puts "Hello from Crystal"
```
</details>

`ada <code>` - GNAT
<details>
<summary>Example</summary>

```ada
with Ada.Text_IO; use Ada.Text_IO;
procedure Hello is
begin
   Put_Line ("Hello from Ada");
end Hello;
```
</details>

`d <code>` - GDC
<details>
<summary>Example</summary>

```d
import std.stdio;
void main() {
    writeln("Hello from D");
}```
</details>

`groovy <code>` - Groovy 2.4.8
<details>
<summary>Example</summary>

```groovy
println "Hello from Groovy"
```
</details>

`dart <code>` - Dart 2.3.1
<details>
<summary>Example</summary>

```dart
main() {
	print("Hello from Dart");
}
```
</details>

`erlang <code>` - Erlang
<details>
<summary>Example</summary>

```erl
-module(tangent).
-export([main/0]).
main() -> io:fwrite("Hello from Erlang\n").
```
</details>

`forth <code>` - GNU FORTH
<details>
<summary>Example</summary>

```
.( Hello from FORTH) CR
```
</details>

`pascal <code>` - Free Pascal Compiler 3.0.0
<details>
<summary>Example</summary>

```pascal
program Tangent(output);
begin
  writeln('Hello from Pascal');
end.
```
</details>

`hack <code>` - HipHop VM 4.8.0
<details>
<summary>Example</summary>

```hack
echo 'Hello from Hack';
```
</details>

`julia <code>` - Julia 0.4.7
<details>
<summary>Example</summary>

```julia
println("Hello from Julia")
```
</details>

`kotlin <code>` - Kotlin 1.3.31
<details>
<summary>Example</summary>

```kotlin
fun main(args : Array<String>) {
    println("Hello from Kotlin")
}
```
</details>

`scala <code>` - Scala 2.12.8
<details>
<summary>Example</summary>

```scala
object Tangent {
  def main(args: Array[String]): Unit = {
    println("Hello from Scala")
  }
}
```
</details>

`typescript <code>` - Typescript 2.1.5 on Node.JS v4.8.2
<details>
<summary>Example</summary>

```ts
console.log("Hello from TypeScript");
```
</details>

`verilog <code>` - Icarus Verilog
<details>
<summary>Example</summary>

```v
module test;
  initial begin
    $display("Hello from Verilog");
  end
endmodule
```
</details>

`wasm <code>` - Webassembly WAVM
<details>
<summary>Example</summary>

```scheme
(module
  (import "env" "_fwrite" (func $__fwrite (param i32 i32 i32 i32) (result i32)))
  (import "env" "_stdout" (global $stdoutPtr i32))
  (import "env" "memory" (memory 1))
  (export "main" (func $main))
  (data (i32.const 8) "Hello from WASM\n")
  (func (export "establishStackSpace") (param i32 i32) (nop))
  (func $main (result i32)
    (local $stdout i32)
    (local.set $stdout (i32.load align=4 (global.get $stdoutPtr)))
    (call $__fwrite
       (i32.const 8)
       (i32.const 1)
       (i32.const 16)
       (local.get $stdout)
    )
    (return (i32.const 0))
  )
)
```
</details>

`scheme <code>` - MIT Scheme 9.1.1
<details>
<summary>Example</summary>

```scheme
(begin
  (display "Hello from Scheme")
  (newline))
```
</details>

`awk <code>` - GNU Awk 4.1.4
<details>
<summary>Example</summary>

```awk
BEGIN { print "Hello from AWK" }
```
</details>

`clojure <code>` - Clojure 1.8.0
<details>
<summary>Example</summary>

```clojure
(println "Hello from Clojure")
```
</details>

`tibasic <code>` - Limited TI-BASIC interpreter from [patrickfeltes/ti-basic-interpreter](https://github.com/patrickfeltes/ti-basic-interpreter/)
<details>
<summary>Example</summary>

```js
Disp "Hello from TI-BASIC"
```
</details>

`batch <code>` - WINE's cmd.exe
<details>
<summary>Example</summary>

```bat
@echo off
echo Hello from Batch
```
</details>

`racket <code>` - Racket 6.7
<details>
<summary>Example</summary>

```lisp
#lang racket/base
(print "Hello from Racket")
```
</details>

`Rust <code>` - rustc 1.24.1
<details>
<summary>Example</summary>

```rust
fn main() {
	println!("Hello from Rust");
}
```
</details>
