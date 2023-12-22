// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "./OwnableBase.sol";

/**
 * @title MoonCatRescueTraits
 * @dev Combining the static data available in the MoonCatRescue contract, with additional trait-parsing logic.
 */
contract MoonCatRescueTraits is OwnableBase {
  enum Modes { Inactive, Disabled, Test, Live }
  Modes public constant mode = Modes.Live;

  bytes16 public constant imageGenerationCodeMD5 = 0xdbad5c08ec98bec48490e3c196eec683; // use this to verify mooncatparser.js the cat image data generation javascript file.

  string public constant name = "MoonCats";
  string public constant symbol = unicode"🐱"; // unicode cat symbol
  uint8 public constant decimals = 0;

  uint256 public constant totalSupply = 25600;
  uint16 public constant remainingCats = 0;
  uint16 public constant remainingGenesisCats = 160;
  uint16 public constant rescueIndex = 25440;

  bytes32[3180] private rescueOrderCompact;
  bytes32 public constant searchSeed = 0x8363e7eaae8e35b1c2db100a7b0fb9db1bc604a35ce1374d882690d0b1d888e2;

  mapping (bytes5 => uint128) internal MappedColors;
  bool public finalized = false;

  constructor (address documentationAddress) OwnableBase(documentationAddress) {}

  /* Human-friendly trait names */

  string[2] public facingNames = ["left", "right"];
  string[4] public expressionNames = ["smiling", "grumpy", "pouting", "shy"];
  string[4] public patternNames = ["pure", "tabby", "spotted", "tortie"];
  string[4] public poseNames = ["standing", "sleeping", "pouncing", "stalking"];

  function setRescueOrders (uint256 offset, bytes32[] calldata hexIds) public onlyRole(ADMIN_ROLE) {
    require(!finalized, "metadata is finalized");
    for(uint256 i = 0; i < hexIds.length; i++) {
      rescueOrderCompact[offset + i] = hexIds[i];
    }
  }

  /**
   * @dev Add hard-coded color palettes for specific MoonCat hex IDs.
   *
   * Due to the differences between Javascript math and Solidity math, some MoonCat color conversions end up rounded differently
   * in the two languages. For the ones that cannot be calculated dynamically (edge-cases), they get hard-coded into the contract here.
   */
  function mapColors (bytes5[] calldata keys, uint128[] calldata vals) public onlyRole(ADMIN_ROLE) {
    require(!finalized, "metadata is finalized");
    require(keys.length == vals.length, "mismatched lengths");
    for (uint i = 0; i < keys.length; i++) {
      MappedColors[keys[i]] = vals[i];
    }
  }

  function finalize () public onlyRole(ADMIN_ROLE) {
    finalized = true;
  }

  /* Traits */

  /**
   * @dev For a given MoonCat rescue order, return the hex ID of that MoonCat.
   */
  function catIdOf (uint256 rescueOrder) public view returns (bytes5 catId) {
    catId = bytes5(rescueOrderCompact[rescueOrder / 8] << ((rescueOrder % 8) * 32));
    catId = catId >> 8;
    if (
      (rescueOrder >= 84 && rescueOrder <= 99) ||
      (rescueOrder >= 524 && rescueOrder <= 539) ||
      (rescueOrder >= 1102 && rescueOrder <= 1117) ||
      (rescueOrder >= 1749 && rescueOrder <= 1764) ||
      (rescueOrder >= 2364 && rescueOrder <= 2379) ||
      (rescueOrder >= 2876 && rescueOrder <= 2891)
    ) {
      catId = catId | 0xff00000000;
    }
  }

  /**
   * @dev For a given MoonCat rescue order, return the calendar year it was rescued in.
   */
  function rescueYearOf (uint256 rescueOrder) public pure returns (uint16) {
    if (rescueOrder <= 3364) {
      return 2017;
    } else if (rescueOrder <= 5683) {
      return 2018;
    } else if (rescueOrder <= 5754) {
      return 2019;
    } else if (rescueOrder <= 5757) {
      return 2020;
    } else {
      return 2021;
    }
  }

  /**
   * @dev For a given MoonCat hex ID, extract the trait data from the "K" byte.
   */
  function kTraitsOf (bytes5 catId) public pure returns (
    bool genesis,
    bool pale,
    uint8 facing,
    uint8 expression,
    uint8 pattern,
    uint8 pose
  ) {
    uint40 c = uint40(catId);
    uint8 classification = uint8(c >> 32);
    require(classification == 0 || classification == 255, "Invalid Classification");

    genesis = (classification == 255);

    uint8 r = uint8(c >> 16);
    uint8 g = uint8(c >> 8);
    uint8 b = uint8(c);

    require(!genesis || (r == 0 && g == 12 && b == 167), "Invalid Genesis Id");

    pale = ((c >> 31) & 1) == 1;
    if (genesis) {
      uint8 k = uint8(c >> 24);
      bool even_k = k % 2 == 0;
      pale = (even_k && pale) || (!even_k && !pale);
    }

    facing = uint8((c >> 30) & 1);
    expression = uint8((c >> 28) & 3);
    pattern = uint8((c >> 26) & 3);
    pose = uint8((c >> 24) & 3);
  }

  /**
   * @dev For a given MoonCat rescue order, extract the trait data from the "K" byte.
   */
  function kTraitsOf (uint256 rescueOrder) public view returns (
    bool genesis,
    bool pale,
    uint8 facing,
    uint8 expression,
    uint8 pattern,
    uint8 pose
  ) {
    require(rescueOrder < 25440, "Invalid Rescue Order");
    return kTraitsOf(catIdOf(rescueOrder));
  }

  /**
   * @dev For a given MoonCat hex ID, extract the trait data in a human-friendly format.
   */
  function traitsOf (bytes5 catId) public view returns (
    bool genesis,
    bool pale,
    string memory facing,
    string memory expression,
    string memory pattern,
    string memory pose
  ) {
    (bool genesisBool, bool paleBool, uint8 facingInt, uint8 expressionInt, uint8 patternInt, uint8 poseInt) = kTraitsOf(catId);
    return (
      genesisBool,
      paleBool,
      facingNames[facingInt],
      expressionNames[expressionInt],
      patternNames[patternInt],
      poseNames[poseInt]
    );
  }

  /**
   * @dev For a given MoonCat rescue order, extract the trait data in a human-friendly format.
   */
  function traitsOf (uint256 rescueOrder) public view returns (
    bool genesis,
    bool pale,
    string memory facing,
    string memory expression,
    string memory pattern,
    string memory pose,
    bytes5 catId,
    uint16 rescueYear
  ) {
    require(rescueOrder < 25440, "Invalid Rescue Order");
    catId = catIdOf(rescueOrder);
    (genesis, pale, facing, expression, pattern, pose) = traitsOf(catId);
    rescueYear = rescueYearOf(rescueOrder);
  }

  /* Hue Computation */

  uint256 constant private ONE = 1e15;
  uint256 constant private SIX = 6e15;
  uint256 constant private HUNDREDTH = 1e13;

  /**
   * @dev Convert a color from the RGB colorspace to HSL and return the Hue component.
   * Core function that was originally parsed in Javascript, translated to Solidity.
   */
  function RGBToHue (uint256 r, uint256 g, uint256 b) public pure returns (uint256) {
    r = r * ONE / 255;
    g = g * ONE / 255;
    b = b * ONE / 255;

    uint256 cMax = r;
    uint256 cMin = r;

    if (g > r || b > r) {
      if (g > b) {
        cMax = g;
      } else {
        cMax = b;
      }
    }

    if (g < r || b < r) {
      if (g < b) {
        cMin = g;
      } else {
        cMin = b;
      }
    }

    uint256 delta = cMax - cMin;

    uint256 numerator;
    uint256 offset = 0;
    bool neg = false;

    if (delta == 0) {
      return 0;
    } else if (cMax == r) {
      if (g >= b) {
        numerator = g - b;
      } else {
        numerator = b - g;
        neg = true;
      }
    } else if (cMax == g) {
      if (b >= r) {
        numerator = b - r;
      } else {
        numerator = r - b;
        neg = true;
      }
      offset = 2 * ONE;
    } else {
      if (r >= g) {
        numerator = r - g;
      } else {
        numerator = g - r;
        neg = true;
      }
      offset = 4 * ONE;
    }

    uint256 hue = ((numerator * ONE) + (delta / 2)) / delta;
    if (neg) {
      hue = offset + SIX - hue;
    } else {
      hue = hue + offset;
    }

    while (hue > SIX) {
      hue -= SIX;
    }

    return hue * 60;
  }

  /* Colors */

  /**
   * @dev For a given MoonCat hex ID, return the Hue degree value for that MoonCat.
   */
  function hueIntOf (bytes5 catId) public view returns (uint16) {
    uint40 c = uint40(catId);
    bool invert = ((c >> 31) & 1) == 1;
    if (c >= 1095216663719) {
      bool even_k = uint8(c >> 24) % 2 == 0;
      if ((even_k && invert) || (!even_k && !invert)) {
        return 2000;
      } else {
        return 1000;
      }
    }

    uint16 offset = 0;
    uint128 mapped = MappedColors[catId];
    if (mapped != 0 && (mapped & 1 == 1)) {
        offset = 1;
    }
    uint8 r = uint8(c >> 16);
    uint8 g = uint8(c >> 8);
    uint8 b = uint8(c);

    uint256 hue = RGBToHue(r, g, b) + 2000; // 2000 is a correction factor

    return uint16(hue / ONE) - offset;
  }

  /**
   * @dev For a given MoonCat rescue order, return the Hue degree value for that MoonCat.
   */
  function hueIntOf (uint256 rescueOrder) public view returns (uint16) {
    require(rescueOrder < 25440, "Invalid Rescue Order");
    return hueIntOf(catIdOf(rescueOrder));
  }

  /**
   * @dev For a given MoonCat hex ID, return the RGB glow color for it.
   */
  function glowOf (bytes5 catId) public pure returns (uint8[3] memory) {
    uint40 c = uint40(catId);
    uint8[3] memory glow;
    glow[0] = uint8(c >> 16);
    glow[1] = uint8(c >> 8);
    glow[2] = uint8(c);
    return glow;
  }

  /**
   * @dev For a given MoonCat rescue order, return the RGB glow color for it.
   */
  function glowOf (uint256 rescueOrder) public view returns (uint8[3] memory) {
    require(rescueOrder < 25440, "Invalid Rescue Order");
    return glowOf(catIdOf(rescueOrder));
  }

}
