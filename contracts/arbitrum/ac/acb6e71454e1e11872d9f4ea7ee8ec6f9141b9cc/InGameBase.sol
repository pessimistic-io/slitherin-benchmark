// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./IPeekABoo.sol";
import "./ITraits.sol";
import "./ILevel.sol";
import "./IERC20Upgradeable.sol";

contract InGameBase {
    // tokenId => traitType => traitId => bool
    mapping(uint256 => mapping(uint256 => mapping(uint256 => bool)))
        public boughtTraits;
    mapping(uint256 => bool[6]) public boughtAbilities;
    // tokenId => boughtTraitCountByRarity [common,uncommon,...]
    mapping(uint256 => uint256[4]) public boughtTraitCount;

    IPeekABoo public peekaboo;
    ITraits public traits;
    ILevel public level;
    IERC20Upgradeable public boo;
    IERC20Upgradeable public magic;
    uint256 public traitPriceRate;
    uint256 public abilityPriceRate;
}

