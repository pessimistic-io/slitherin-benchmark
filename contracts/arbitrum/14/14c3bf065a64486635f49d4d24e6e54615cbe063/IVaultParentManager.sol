// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IVaultParentManager {
    function requestBridgeToChain(
        uint16 dstChainId,
        address asset,
        uint256 amount,
        uint256 minAmountOut
    ) external payable;

    function requestCreateSibling(uint16 newChainId) external payable;

    function sendBridgeApproval(uint16 dstChainId) external payable;

    function changeManager(address newManager) external payable;

    function setDiscountForHolding(
        uint256 tokenId,
        uint256 streamingFeeDiscount,
        uint256 performanceFeeDiscount
    ) external;
}

