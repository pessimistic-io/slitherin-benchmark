// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;


import { IERC20 } from "./IERC20.sol";


contract ERC20OnceSetter {
    IERC20 public TOKEN;


    function setToken(
        IERC20 _token
    ) public {
        require(address(TOKEN) == address(0), "Token has been already set");
        TOKEN = _token;
    }
}

