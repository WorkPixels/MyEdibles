# MyEdibles

A clean, modular, and draggable action bar addon for **World of Warcraft**, providing dedicated consumable and utility bars for **Food & Drink**, **Potions & Elixirs**, **Bandages**, **Bombs**, **Stones & Weightstones**, and **Camping Items**.

Supports **World of Warcraft: Forever**, **The Burning Crusade Classic (Anniversary)**, **Classic Era**, and **Retail/Modern engines**.

---

## Features

- **Dedicated Consumable Bars:**
  - **MyEdibles**: Food & Drink, with automatic smart separation into dual Food/Drink rows or single merged row.
  - **MyPotions**: Health potions, mana potions, elixirs, flasks, and healthstones.
  - **MyBandAids**: Bandages and first-aid items.
  - **MyBombs**: Explosives, grenades, dynamite, and sapper charges.
  - **MyStones**: Sharpening stones, weightstones, and weapon temporary enhancements.
  - **MyCamping**: Campfire kits (Basic, Journeyman, Expert) and profession camp items (Tiers 1–3) in *World of Warcraft: Forever*.
  - **MyKeys**: Blacksmithing skeleton keys (Silver, Golden, Truesilver, Arcanite, Cobalt, Titanium) and Engineering lock bombs (Small, Large, Powerful, Elemental Seaforium Charges).
- **Full Customization per Bar:**
  - Independent orientation (Horizontal or Vertical).
  - Independent scale, button size, spacing, and maximum item count.
  - "Hide when inventory is empty" toggle.
  - Lock/unlock draggable handles (`::`).
  - Safe screen clamping and high frame strata so bars never slip behind default action bars.
- **Whitelist & Blacklist System:**
  - Easily blacklist items you never want displayed on your bars.
  - Whitelist custom items or toys to force them onto any bar.
  - Drag-and-drop item support and manual item ID entry.
  - Built-in **Inventory Scanner (Bags tab)** with one-click `+WL` / `+BL` buttons for each bar.
- **Modern Compatibility Layer:**
  - Automatically adapts to newer `C_Container` and `C_Item` APIs while maintaining fallbacks for Classic Era.
- **Account-Wide Architecture:**
  - Clean, unified SavedVariables (`MyEdiblesDB`) that reliably persist across reloads and characters.

---

## Slash Commands

```text
/myedibles          Toggle the configuration panel
/edibles            Alternative shortcut for configuration panel
/myedibles lock     Lock all bars in place
/myedibles unlock   Unlock all bars to move them
/myedibles reset    Reset all bars to default positions above your action bar
```

---

## Installation

1. Download or clone this repository.
2. Place the `MyEdibles` folder into your World of Warcraft AddOns directory:
   - **WoW: Forever:** `World of Warcraft\_forever_\Interface\AddOns\MyEdibles`
   - **TBC Anniversary:** `World of Warcraft\_anniversary_\Interface\AddOns\MyEdibles`
   - **Classic Era:** `World of Warcraft\_classic_\Interface\AddOns\MyEdibles`
3. Launch or `/reload` World of Warcraft.

---

## Author

- **KD** ([WorkPixels](https://github.com/WorkPixels))
