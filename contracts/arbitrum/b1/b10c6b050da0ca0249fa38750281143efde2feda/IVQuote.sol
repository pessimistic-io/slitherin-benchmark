// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";

interface IVQuote is IERC20 {
    function mint(address account, uint256 amount) external;

    function burn(uint256 amount) external;

    function authorize(address vPoolWrapper) external;
}

