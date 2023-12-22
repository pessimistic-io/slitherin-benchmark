// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IOracle.sol";

interface IOracleOffChainPyth is IOracle {

    event NewValue(uint256 indexed timestamp, uint256 indexed value);

    function delayAllowance() external view returns (uint256);

    function lastSignatureTimestamp() external view returns (uint256);

    function oracleManager() external view returns (address);

    function pythId() external view returns (bytes32);

    function updateValue(uint256 timestamp_, uint256 value_) external returns (bool);

}

