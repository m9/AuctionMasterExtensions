# AuctionMaster Extensions

Extras for AuctionMaster. Does not edit its files.

## Crates

A Crates tab in the panel beside the Buy tab. Lists Waylaid Crates with their cheapest bundle.

- Cheapest: Per Favor or Overall (crate and bundle together).
- Each crate shows its Favor, the cost per Favor, what to buy and the total.
- Owned crates and materials cost nothing. Bags and bank count.
- `~` marks an estimate from the last scan.
- Update searches the items for exact prices. Stop ends it.
- Click a row to open the item with the quantity set.
- Add to list puts the crate and its bundle on AuctionMaster's shopping list. Each click adds one more.
- Crates above your level are hidden.

Artisan crates show `?` Favor. It is not known yet.

If AuctionMaster changes its panel, the tab is not added and one line is printed.

## Versions

The version has two parts: `11.6.6-1.0` is our version 1.0, made for AuctionMaster 11.6.6.

## Install

Copy the folder to `_forever_\Interface\AddOns\AuctionMasterExtensions`. Needs AuctionMaster.

## Release tools

`luajit tools/build.lua` - makes `out/AuctionMasterExtensions-<version>.zip`. Refuses a `-dev` version unless `--dev` is given.

## Test

`luajit tests/test.lua` - runs the addon against a mock.
