// SPDX-License-Identifier: MIT



pragma solidity >=0.5.0;

import "./IERC20Base.sol";

interface IERC20 is IERC20Base {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

