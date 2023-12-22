//SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./Structs.sol";

interface IMBusSupport is Structs {
    //CrossChainData encode
    function getFee(
        SwapBaseInfo memory _baseInfo,
        uint256 _crossFee,
        bool _swap,
        SwapInfo memory _swapInfo
    ) external view returns (bytes memory, uint256 _fee);

    function _crossChainSwap(
        SwapBaseInfo memory _baseInfo,
        uint256 _crossFee,
        uint64 _dstChainId,
        address _dstContract,
        address _crossToken,
        uint32 _maxSlippage,
        bool _swap,
        SwapInfo memory _swapInfo
    ) external payable returns (bytes32 _transferId);

    function messageBus() external view returns (address);
}

