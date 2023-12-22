// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
import "./IERC721.sol";

interface ICamelotNFTPool is IERC721 {
    function createPosition(uint256 amount, uint256 lockDuration) external;

    function lastTokenId() external view returns (uint256);

    function addToPosition(uint256 tokenId, uint256 amountToAdd) external;

    function withdrawFromPosition(uint256 tokenId, uint256 amountToWithdraw) external;

    function harvestPosition(uint256 tokenId) external;

    function yieldBooster() external view returns (address);

    function emergencyWithdraw(uint256 tokenId) external;
}

