// SPDX-License-Identifier: MIT

pragma solidity >=0.5.16;

import "./IERC20Upgradeable.sol";

interface ISpeedMarketsAMM {
    function sUSD() external view returns (IERC20Upgradeable);
}

