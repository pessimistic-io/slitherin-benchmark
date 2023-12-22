//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

// Interfaces
import {IERC20} from "./IERC20.sol";
import {OneInchZapLib} from "./OneInchZapLib.sol";

interface ILPVault {
    // Token being deposited
    function depositToken() external view returns (IERC20);

    // Flag to see if any funds have been borrowed this epoch
    function borrowed() external view returns (bool);
}

interface IBearLPVault is ILPVault {
    function borrow(
        uint256[2] calldata _minTokenOutputs,
        uint256 _min2Crv,
        address _intermediateToken,
        OneInchZapLib.SwapParams[2] calldata _swapParams
    )
        external
        returns (uint256[2] memory);

    function repay(
        uint256[2] calldata _minOutputs,
        uint256 _minLpTokens,
        address _intermediateToken,
        OneInchZapLib.SwapParams[2] calldata _swapParams
    )
        external
        returns (uint256);
}

interface IBullLPVault is ILPVault {
    function borrow(uint256[2] calldata _minTokenOutputs) external returns (uint256);

    function repay(
        uint256 _minPairTokens,
        address[] calldata _inTokens,
        uint256[] calldata _inTokenAmounts,
        OneInchZapLib.SwapParams[] calldata _swapParams
    )
        external
        returns (uint256);
}

