// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IScratchEmTreasury {
    function gameDeposit(address token, uint256 amount) external;

    function gameWithdraw(address to, address token, uint256 amount) external;

    function gameResult(address to, address token, uint256 amount) external;

    function claimRewardsByGame(
        address user,
        address token,
        uint amount
    ) external;

    function nonceLock(
        uint nonce,
        address user,
        address token,
        uint256 amount
    ) external payable;

    function nonceUnlock(
        uint nonce,
        uint8 swapType,
        address[] calldata path,
        uint burnCut,
        uint afterTransferCut,
        address afterTransferToken,
        address afterTransferAddress
    ) external;

    function nonceRevert(uint nonce) external;
}

