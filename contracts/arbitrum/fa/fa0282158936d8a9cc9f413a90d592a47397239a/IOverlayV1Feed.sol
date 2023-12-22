// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import "./Oracle.sol";

interface IOverlayV1Feed {
    // immutables
    function feedFactory() external view returns (address);

    function microWindow() external view returns (uint256);

    function macroWindow() external view returns (uint256);

    // returns freshest possible data from oracle
    function latest() external view returns (Oracle.Data memory);
}

