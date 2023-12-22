// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./IERC20.sol";

interface IOracle {
    error ConnectorShouldBeNone();
    error PoolNotFound();
    error PoolWithConnectorNotFound();

    function getRate(IERC20 srcToken, IERC20 dstToken, IERC20 connector) external view returns (uint256 rate, uint256 weight);
}

