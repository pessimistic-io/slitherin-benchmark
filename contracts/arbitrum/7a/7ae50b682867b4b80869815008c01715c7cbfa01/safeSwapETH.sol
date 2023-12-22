// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.6.12;

import "./SafeToken.sol";
import "./interfaces_IWETH.sol";
import "./IBEP20.sol";

contract safeSwapETH {
    /* ========== CONSTANTS ============= */

    address private constant WETH = 0x8DfbB066e2881C85749cCe3d9ea5c7F1335b46aE;

    /* ========== CONSTRUCTOR ========== */

    constructor() public {}

    receive() external payable {}

    /* ========== FUNCTIONS ========== */

    function withdraw(uint256 amount) external {
        require(IBEP20(WETH).balanceOf(msg.sender) >= amount, "Not enough Tokens!");

        IBEP20(WETH).transferFrom(msg.sender, address(this), amount);

        IWETH(WETH).withdraw(amount);

        SafeToken.safeTransferETH(msg.sender, amount);
    }
}

