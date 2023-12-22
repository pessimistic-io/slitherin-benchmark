// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {NATIVE_TOKEN} from "./constants_Tokens.sol";
import {IERC20} from "./IERC20.sol";
import {Address} from "./Address.sol";
import {     SafeERC20 } from "./SafeERC20.sol";

library GelatoTokenUtils {
    function transfer(
        address _token,
        address _to,
        uint256 _amount
    ) internal {
        _token == NATIVE_TOKEN
            ? Address.sendValue(payable(_to), _amount)
            : SafeERC20.safeTransfer(IERC20(_token), _to, _amount);
    }

    function getBalance(address token, address user)
        internal
        view
        returns (uint256)
    {
        return
            token == NATIVE_TOKEN
                ? user.balance
                : IERC20(token).balanceOf(user);
    }
}

