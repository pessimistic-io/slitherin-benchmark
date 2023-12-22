// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IScratchGames {
    function scratchAndClaimAllCardsTreasury() external;

    function scratchAllCardsTreasury() external;

    function burnAllCardsTreasury() external;

    function endMint(uint256 _nonce, uint256[] calldata rngList) external;
}

