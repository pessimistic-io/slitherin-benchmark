//SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

interface Structs {
    struct SwapBaseInfo {
        address _from;
        address _to;
        uint256 _amount;
        uint256 _minReturn;
    }

    struct CrossChainData {
        address _receiver;
        SwapBaseInfo _baseInfo;
        bool _swap;
        SwapInfo _swapInfo;
        uint256 _crossFee;
    }

    struct SwapInfo {
        uint8 _swapType; //1: def, 2: 1inch
        bytes _swapData; //Different struct entities
    }

    enum ExecutionStatus {
        Fail,
        Success,
        Retry
    }

    struct CrossParams {
        address _token;
        uint256 _amount;
        uint256 _deadline;
        bytes _signature;
        uint32 _cbridgeMaxSlippage;
        uint64 _cbridgeNonce;
    }
}

