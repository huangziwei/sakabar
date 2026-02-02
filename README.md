# Sakabar 酒場

Sakabar [^1] is a macOS menubar app for managing local, self-made [^2] services.

```sh
# clone the repo
git clone https://github.com/huangziwei/sakabar

# make sure Xcode Command Line Tools are installed
xcode-select --install

# build
./build.sh

# run
open build/Sakabar.app
```

[^1]: I want to have a `bar` in the name, and somehow 酒場 already means a bar and has the sound `ba` (場) in it.
[^2]: Actually, I want to say "homebrew" here—[^3]"A bar that serves homebrew services" fits very well—but [Homebrew](https://brew.sh) already offers [services](https://docs.brew.sh/Manpage#services-subcommand), so it’s better not to overload the term, especially when there's also a [menubar app](https://github.com/validatedev/BrewServicesManager) for `brew services`.
[^3]: TIL how to type en- and em-dash on macOS: `– = Option + -` and `— = Shift + Option + -`. But the most diabolic thing about this is that VS Code cannot render the difference between en- and em-dash properly (at least, with the font I am using).
