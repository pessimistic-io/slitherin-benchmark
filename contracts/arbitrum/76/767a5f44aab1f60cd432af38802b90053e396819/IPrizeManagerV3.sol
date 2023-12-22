// SPDX-License-Identifier: MIT

pragma solidity =0.8.17;
pragma experimental ABIEncoderV2;

interface IPrizeManagerV3 {
    function createPrize(uint256, address[] memory, uint256[] memory, address, uint256) external;
    function createSidePrize(uint256, address[] memory, uint256[] memory) external;
    function newWinners(uint256, address[] memory) external;
    function claimPrize(uint256, address) external;
    function claimAll(uint256[] memory, address) external;
    function batchClaim(uint256[] memory, address[] memory) external;
    function updatePrize(uint256, uint256) external;
    function claimAll(uint256) external;
}
