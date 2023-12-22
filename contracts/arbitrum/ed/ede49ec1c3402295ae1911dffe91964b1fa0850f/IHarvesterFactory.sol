//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";

import "./IMiddleman.sol";

interface IHarvesterFactory {
    function magic() external view returns (IERC20);
    function middleman() external view returns (IMiddleman);
    function getAllHarvesters() external view returns (address[] memory);
}
