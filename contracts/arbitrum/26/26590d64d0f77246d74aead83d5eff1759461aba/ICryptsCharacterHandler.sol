//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ICorruptionCryptsInternal.sol";

interface ICryptsCharacterHandler {
    function handleStake(CharacterInfo memory, address _user) external;

    function handleUnstake(CharacterInfo memory, address _user) external;

    function getCorruptionDiversionPointsForToken(uint32 _tokenId) external view returns(uint24);
    function getCorruptionCraftingClaimedPercent(uint32 _tokenId) external returns(uint32);
}
