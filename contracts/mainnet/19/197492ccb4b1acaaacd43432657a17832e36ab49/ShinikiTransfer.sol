// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ISignatureVerifier.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract ShinikiTransfer {
    using SafeERC20 for IERC20;

    constructor() {}

    receive() external payable {}

    /**
    @notice Transfer ETH
     * @param receiver 'address' receiver ETH
     * @param amount 'uint256' number ETH to transfer
     */
    function transferETH(address receiver, uint256 amount) internal {
        (bool success, ) = receiver.call{value: amount}("");
        require(success, "transfer failed.");
    }

    /**
    @notice Transfer token
     * @param token 'address' token
     * @param sender 'address' sender token
     * @param receiver 'address' receiver token
     * @param amount 'uint256' number token to transfer
     */
    function transferToken(
        address token,
        address sender,
        address receiver,
        uint256 amount
    ) internal {
        require(
            IERC20(token).balanceOf(sender) >= amount,
            "token insufficient balance"
        );
        IERC20(token).safeTransferFrom(sender, receiver, amount);
    }
}

