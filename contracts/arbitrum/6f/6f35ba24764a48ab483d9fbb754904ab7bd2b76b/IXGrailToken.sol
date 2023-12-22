// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IERC20.sol";

interface IXGrailToken is IERC20 {
    function usageAllocations(address userAddress, address usageAddress) external view returns (uint256 allocation);

    function allocateFromUsage(address userAddress, uint256 amount) external;
    function convertTo(uint256 amount, address to) external;
    function deallocateFromUsage(address userAddress, uint256 amount) external;

    function isTransferWhitelisted(address account) external view returns (bool);
    function redeem(uint256 xGrailAmount, uint256 duration) external;
    function finalizeRedeem(uint256 redeemIndex) external;

    function getUserRedeem(address userAddress, uint256 redeemIndex) external view returns (uint256 grailAmount, uint256 xGrailAmount, uint256 endTime, address dividendsContract, uint256 dividendsAllocation);
    function getUserRedeemsLength(address userAddress) external view returns (uint256);

    function minRedeemDuration() external view returns (uint256);
}
