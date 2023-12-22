// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import { ICoreSwapHandlerV1 } from "./ICoreSwapHandlerV1.sol";

interface IZeroExAdapterStructs {
    struct ZeroExSwapParams {
        uint256 deadline;
        bytes swapData;
    }

    /// @dev Needed for core
    function decodeParams(bytes memory data) external pure returns (ZeroExSwapParams memory);

    struct BatchFillData {
        address inputToken;
        address outputToken;
        uint256 sellAmount;
        WrappedBatchCall[] calls;
    }

    struct WrappedBatchCall {
        bytes4 selector;
        uint256 sellAmount;
        bytes data;
    }

    struct MultiHopFillData {
        address[] tokens;
        uint256 sellAmount;
        WrappedMultiHopCall[] calls;
    }

    struct WrappedMultiHopCall {
        bytes4 selector;
        bytes data;
    }
}

interface IZeroExSwapHandler is ICoreSwapHandlerV1 {}

