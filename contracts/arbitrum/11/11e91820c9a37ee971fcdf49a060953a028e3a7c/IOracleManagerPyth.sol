// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./INameVersion.sol";
import "./IAdmin.sol";

interface IOracleManagerPyth is INameVersion, IAdmin {

    event NewOracle(bytes32 indexed symbolId, address indexed oracle);

    function getOracle(bytes32 symbolId) external view returns (address);

    function getOracle(string memory symbol) external view returns (address);

    function setOracle(address oracleAddress) external;

    function delOracle(bytes32 symbolId) external;

    function delOracle(string memory symbol) external;

    function value(bytes32 symbolId) external view returns (uint256);

    function timestamp(bytes32 symbolId) external view returns (uint256);

    function getValue(bytes32 symbolId) external view returns (uint256);

    function getValueWithJump(bytes32 symbolId) external returns (uint256 val, int256 jump);

    function lastSignatureTimestamp(bytes32 pythId) external view returns (uint256);

    function getUpdateFee(uint256 length) external view returns (uint256);

    function updateValues(bytes[] memory vaas, bytes32[] memory ids) external payable returns (bool);

}

