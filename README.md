# Flor do Mar

Flor do Mar is a Haskell-first naval combat prototype. The first slice uses a shared combat library and a Reflex-DOM browser client.

## Toolchain

The Nix flake pins the development environment to GHC 9.10.3. This is the newest GHC currently chosen for the project that works with both the available Reflex-DOM package set and a matching Haskell Language Server in nixpkgs.

## Commands

Enter the development shell:

```sh
nix develop
```

Build everything:

```sh
cabal build all
```

Run combat tests without opening a browser:

```sh
cabal test all
```

Run the local Reflex-DOM client:

```sh
cabal run flor-do-mar-client
```

Then open `http://localhost:3911/`.
