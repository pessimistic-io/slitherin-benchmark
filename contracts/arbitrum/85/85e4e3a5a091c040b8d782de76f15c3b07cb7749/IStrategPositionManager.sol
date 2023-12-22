// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {DataTypes} from "./DataTypes.sol";

interface IStrategPositionManager {
    struct RebalanceData {
        bool isBelow;
        bytes data;
        uint256[] partialExecutionEnterDynamicParamsIndex;
        bytes[] partialExecutionEnterDynamicParams;
        uint256[] partialExecutionExitDynamicParamsIndex;
        bytes[] partialExecutionExitDynamicParams;
    }

    function initialized() external view returns (bool);
    function owner() external view returns (address);
    function blockIndex() external view returns (uint256);
    function rebalance(RebalanceData memory _data) external;
    function initialize(address _owner, uint256 _blockIndex, bytes memory _params) external;
}

