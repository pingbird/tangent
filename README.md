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
`qstart` - Start the VM [trusted only]\
`qrestart` - Restart the VM [trusted only]\
`qclean` - Revert the VM state to a clean snapshot [trusted only]

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

<details><summary>`sh <code>` - Standard /bin/sh</summary>
<p>

#### yes, even hidden code blocks!

```python
print("hello world!")
```

</p>
</details>

<details><summary>CLICK ME</summary>
<p>

#### yes, even hidden code blocks!

```python
print("hello world!")
```

</p>
</details>

<details><summary>CLICK ME</summary>
<p>

#### yes, even hidden code blocks!

```python
print("hello world!")
```

</p>
</details>
