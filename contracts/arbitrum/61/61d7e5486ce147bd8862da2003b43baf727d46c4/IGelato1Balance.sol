// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {IERC20} from "./IERC20.sol";

interface IGelato1Balance {
    function depositToken(
        address sponsor,
        IERC20 token,
        uint256 amount
    ) external;
}

