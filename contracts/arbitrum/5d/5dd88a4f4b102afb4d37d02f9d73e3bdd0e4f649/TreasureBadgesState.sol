//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ITreasureBadges.sol";
import "./ERC1155BaseUpgradeable.sol";

abstract contract TreasureBadgesState is Initializable, ITreasureBadges, ERC1155BaseUpgradeable {
    uint256 public totalMinted;
    uint256 public totalBurned;
    mapping(uint256 => uint256) public tokensMinted;
    mapping(uint256 => uint256) public tokensBurned;

    function __TreasureBadgesState_init() internal onlyInitializing {
        __ERC1155BaseUpgradeable_init();
    }
}

