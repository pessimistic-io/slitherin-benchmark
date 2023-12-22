// SPDX-License-Identifier: BSD-4-Clause

pragma solidity ^0.8.13;

import { AbstractBhavishSDK } from "./AbstractBhavishSDK.sol";
import { IBhavishNativeSDK, IBhavishPredictionNative } from "./IBhavishNativeSDK.sol";
import { IBhavishPrediction } from "./IBhavishPrediction.sol";
import { BhavishSwap } from "./BhavishSwap.sol";
import { Address } from "./Address.sol";
import { SafeERC20, IERC20 } from "./SafeERC20.sol";

contract NativeSDK is AbstractBhavishSDK, IBhavishNativeSDK {
    using Address for address;
    using SafeERC20 for IERC20;

    BhavishSwap public bhavishSwap;

    constructor(
        IBhavishPredictionNative[] memory _bhavishPrediction,
        bytes32[] memory _underlying,
        bytes32[] memory _strike,
        BhavishSwap _bhavishSwap
    ) {
        require(_bhavishPrediction.length == _underlying.length, "Invalid array arguments passed");
        require(_strike.length == _underlying.length, "Invalid array arguments passed");
        require(address(_bhavishSwap).isContract(), "Swapper is not a contract");
        bhavishSwap = _bhavishSwap;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        for (uint256 i = 0; i < _bhavishPrediction.length; i++) {
            predictionMap[_underlying[i]][_strike[i]] = _bhavishPrediction[i];
            activePredictionMap[_bhavishPrediction[i]] = true;
        }
    }

    function _getNativePredictionMap(IBhavishPrediction _bhavishPrediction)
        private
        pure
        returns (IBhavishPredictionNative bhavishPrediction)
    {
        return IBhavishPredictionNative(address(_bhavishPrediction));
    }

    function predict(
        PredictionStruct memory _predStruct,
        address _userAddress,
        address _provider
    ) external payable override {
        IBhavishPredictionNative bhavishPrediction = _getNativePredictionMap(
            predictionMap[_predStruct.underlying][_predStruct.strike]
        );

        require(address(bhavishPrediction) != address(0), "Prediction Market for the asset is not present");
        require(activePredictionMap[bhavishPrediction], "Prediction Market for the asset is not active");

        address userAddress_;
        if (address(msg.sender).isContract() && validContracts[msg.sender]) {
            userAddress_ = _userAddress;
        } else {
            require(msg.sender == _userAddress, "Buyer and msg.sender cannot be different");
            userAddress_ = msg.sender;
        }

        if (_predStruct.directionUp) bhavishPrediction.predictUp{ value: msg.value }(_predStruct.roundId, userAddress_);
        else bhavishPrediction.predictDown{ value: msg.value }(_predStruct.roundId, userAddress_);

        _populateProviderInfo(_provider, msg.value);
    }

    function predictWithGasless(PredictionStruct memory _predStruct, address _provider) external payable override {
        IBhavishPredictionNative bhavishPrediction = _getNativePredictionMap(
            predictionMap[_predStruct.underlying][_predStruct.strike]
        );
        require(address(bhavishPrediction) != address(0), "Prediction Market for the asset is not active");
        require(activePredictionMap[bhavishPrediction], "Prediction Market for the asset is not active");
        require(msg.value > minimumGaslessBetAmount, "Bet amount is not eligible for gasless");

        if (_predStruct.directionUp) bhavishPrediction.predictUp{ value: msg.value }(_predStruct.roundId, msgSender());
        else bhavishPrediction.predictDown{ value: msg.value }(_predStruct.roundId, msgSender());

        _populateProviderInfo(_provider, msg.value);
    }

    function _swapAndPredict(
        BhavishSwap.SwapStruct memory _swapStruct,
        PredictionStruct memory _predStruct,
        uint256 _slippage,
        bool _isGasless,
        address _provider
    ) internal {
        IBhavishPredictionNative bhavishPrediction = _getNativePredictionMap(
            predictionMap[_predStruct.underlying][_predStruct.strike]
        );

        require(address(bhavishPrediction) != address(0), "Prediction Market for the asset is not present");
        require(activePredictionMap[bhavishPrediction], "Prediction Market for the asset is not active");
        // Fetch the path to get the erc20 token address and transfer the amountIn to sdk contract.
        address[] memory path = bhavishSwap.getPath(_swapStruct.fromAsset, _swapStruct.toAsset);
        IERC20(path[0]).safeTransferFrom(msgSender(), address(bhavishSwap), _swapStruct.amountIn);

        uint256[] memory amounts = bhavishSwap.swapExactTokensForETH(_swapStruct, address(this), _slippage);

        if (_isGasless) {
            require(amounts[amounts.length - 1] > minimumGaslessBetAmount, "Bet amount is not eligible for gasless");
        }

        if (_predStruct.directionUp)
            bhavishPrediction.predictUp{ value: amounts[amounts.length - 1] }(_predStruct.roundId, msgSender());
        else bhavishPrediction.predictDown{ value: amounts[amounts.length - 1] }(_predStruct.roundId, msgSender());

        _populateProviderInfo(_provider, amounts[amounts.length - 1]);
    }

    function swapAndPredict(
        BhavishSwap.SwapStruct memory _swapStruct,
        PredictionStruct memory _predStruct,
        uint256 slippage,
        address _provider
    ) external override {
        _swapAndPredict(_swapStruct, _predStruct, slippage, false, _provider);
    }

    function swapAndPredictWithGasless(
        BhavishSwap.SwapStruct memory _swapStruct,
        PredictionStruct memory _predStruct,
        uint256 slippage,
        address _provider
    ) external override {
        _swapAndPredict(_swapStruct, _predStruct, slippage, true, _provider);
    }

    function _claim(
        IBhavishPrediction bhavishPredict,
        uint256[] calldata roundIds,
        address userAddress,
        IBhavishPredictionNative.SwapParams memory _swapParams
    ) internal {
        IBhavishPredictionNative(address(bhavishPredict)).claim(roundIds, userAddress, _swapParams);
    }

    function claim(
        PredictionStruct memory _predStruct,
        uint256[] calldata roundIds,
        IBhavishPredictionNative.SwapParams memory _swapParams
    ) external {
        _claim(predictionMap[_predStruct.underlying][_predStruct.strike], roundIds, msg.sender, _swapParams);
    }

    function claimWithGasless(
        PredictionStruct memory _predStruct,
        uint256[] calldata roundIds,
        IBhavishPredictionNative.SwapParams memory _swapParams
    ) external {
        IBhavishPrediction bhavishPrediction = predictionMap[_predStruct.underlying][_predStruct.strike];

        uint256 avgBetAmount = bhavishPrediction.getAverageBetAmount(roundIds, msgSender());
        require(avgBetAmount > minimumGaslessBetAmount, "Not eligible for gasless");

        _claim(bhavishPrediction, roundIds, msgSender(), _swapParams);
    }
}

