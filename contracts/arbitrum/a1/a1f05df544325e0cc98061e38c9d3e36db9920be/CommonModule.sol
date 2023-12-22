// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "./Chainlink.sol";
import "./IERC20.sol";

abstract contract CommonModule {

    uint256 public constant MAX_UINT_VALUE = type(uint256).max;

    IERC20 public baseToken;
    IERC20 public sideToken;

    uint256 public baseDecimals;
    uint256 public sideDecimals;

    IPriceFeed public baseOracle;
    IPriceFeed public sideOracle;

    function baseToUsd(uint256 amount) public virtual view returns (uint256);
    function usdToBase(uint256 amount) public virtual view returns (uint256);
    function sideToUsd(uint256 amount) public virtual view returns (uint256);
    function usdToSide(uint256 amount) public virtual view returns (uint256);

    uint256[50] private __gap;
}

