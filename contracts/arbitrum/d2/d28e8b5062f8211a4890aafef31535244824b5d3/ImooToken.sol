// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

import "./IERC20.sol";

interface ImooToken is IERC20 {
    function balance() external view returns (uint256);
}

