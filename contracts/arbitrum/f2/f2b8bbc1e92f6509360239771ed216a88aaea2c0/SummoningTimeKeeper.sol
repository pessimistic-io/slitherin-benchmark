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

    function isTokenDoneSummoning(uint256 _tokenId, bool _succeeded) public view returns(bool) {
        return block.timestamp >= _getTokenEndTime(_tokenId, _succeeded);
    }

    function _getTokenEndTime(uint256 _tokenId, bool _succeded) internal view returns(uint256) {
        if(_succeded) {
            uint256 _crystalId = tokenIdToCrystalIdUsed[_tokenId];
            uint256 _reduction = crystalIdToTimeReduction[_crystalId];
            return tokenIdToSummonStartTime[_tokenId] + summoningDuration - _reduction;
        } else {
            return tokenIdToSummonStartTime[_tokenId] + summoningDurationIfFailed;
        }
    }
}
