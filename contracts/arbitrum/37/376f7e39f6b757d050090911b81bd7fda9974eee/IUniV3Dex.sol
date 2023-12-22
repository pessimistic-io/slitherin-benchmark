// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

/**
 * Interface which is a face for Dex handlers implementations. On each chain we might use different
 * dex to swap tokens so we need to abstract generic interface.
 */

interface IUniV3Dex {
    function swap(uint256 _amountIn, address _in, address _out, address _to) external returns (uint amounts);
    function setRoutes(address[][] memory _routes) external;
    function deleteRoutes(address[][] memory _routes) external;
    function getRoute(address _in, address _out) external view returns (address[] memory route);
}

