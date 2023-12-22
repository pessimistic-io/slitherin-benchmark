// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.18;


import { IERC20Tax } from "./IERC20Tax.sol";


contract ERC20TaxReferenced {
    IERC20Tax public TOKEN;

    function setToken(
        IERC20Tax _token
    ) public {
        require(address(TOKEN) == address(0), "Token has been already set");
        TOKEN = _token;
    }
}

