//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./Pilgrimage1155Mapping.sol";

abstract contract PilgrimageTimeKeeper is Initializable, Pilgrimage1155Mapping {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function __PilgrimageTimeKeeper_init() internal initializer {
        Pilgrimage1155Mapping.__Pilgrimage1155Mapping_init();
    }

    function _setPilgrimageStartTime(uint256 _pilgrimageID) internal {
        pilgrimageIdToStartTime[_pilgrimageID] = block.timestamp;
    }

    function isPilgrimageReady(uint256 _pilgrimageID) public view returns(bool) {
        return block.timestamp >= pilgrimageIdToStartTime[_pilgrimageID] + pilgrimageLength;
    }
}
