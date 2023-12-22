// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

library CheeseHeroTypes {
  enum HeroRarity {
    CHEESE,
    N,
    R,
    SR,
    SSR
  }
  struct HeroTraits {
    uint256 id;
    HeroRarity rarity;
    string name;
    string description;
    string image;
    uint256 attributes;
  }
}

