// SPDX-License-Identifier: MIT
import "./IERC20.sol";
import "./SafeERC20.sol";

pragma solidity 0.8.17;

contract TokenDistributor {
    function distribute(
        IERC20 token,
        address[] calldata accounts,
        uint[] calldata amounts
    ) external {
        uint n = accounts.length;
        require(n == amounts.length, "L");

        for (uint i = 0; i < n; i++) {
            SafeERC20.safeTransferFrom(
                token,
                msg.sender,
                accounts[i],
                amounts[i]
            );
        }
    }
}

