//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./EnumerableSetUpgradeable.sol";

import "./SummoningSettings.sol";
import "./ILegionMetadataStore.sol";

abstract contract SummoningTimeKeeper is Initializable, SummoningSettings {

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function __SummoningTimeKeeper_init() internal initializer {
        SummoningSettings.__SummoningSettings_init();
    }

    function _setSummoningStartTime(uint256 _tokenId) internal {
        tokenIdToSummonStartTime[_tokenId] = block.timestamp;
    }

    function isTokenDoneSummoning(uint256 _tokenId) public view returns(bool) {
        return block.timestamp >= tokenIdToSummonStartTime[_tokenId] + summoningDuration;
    }
}
