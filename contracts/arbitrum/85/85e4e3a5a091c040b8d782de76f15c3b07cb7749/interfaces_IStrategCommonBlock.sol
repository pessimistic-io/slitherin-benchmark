// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IStrategPortal} from "./IStrategPortal.sol";

interface IStrategCommonBlock {
    enum BlockExecutionType {
        ENTER,
        EXIT,
        HARVEST
    }

    enum DynamicParamsType {
        NONE,
        PORTAL_SWAP
    }

    struct DynamicSwapParams {
        address fromToken;
        address toToken;
        uint256 value;
        bool isPercent;
    }

    struct DynamicSwapData {
        IStrategPortal.SwapIntegration route;
        address sourceAsset;
        address approvalAddress;
        address targetAsset;
        uint256 amount;
        bytes data;
    }

    struct OracleResponse {
        address vault;
        address[] tokens;
        uint256[] tokensAmount;
    }

    function ipfsHash() external view returns (string memory);
    function dynamicParamsInfo(BlockExecutionType _exec, bytes memory parameters, OracleResponse memory oracleData)
        external
        view
        returns (bool, DynamicParamsType, bytes memory);
}

