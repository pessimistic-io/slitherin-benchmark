// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20ModuleKit} from "./ERC20Actions.sol";
import {ExecutorBase} from "./ExecutorBase.sol";
import {IERC20} from "./ERC20_IERC20.sol";
import {PerpFeesModule} from "./SimplePerpFeesModule.sol";
import {IPositionRouter, IOrderBook, IVault} from "./Interfaces.sol";
import {FeesManager} from "./FeesManager.sol";
import {IExecutorManager} from "./IExecutor.sol";
import {Ownable} from "./Ownable.sol";

contract GMXV1FeesModule is PerpFeesModule, Ownable {
    // ====== Variables ====== //
    IPositionRouter internal gmxPositionRouter;
    IOrderBook internal gmxOrderbook;
    IVault internal gmxVault;

    function setGmxPositionRouter(
        IPositionRouter positionRouter
    ) public onlyOwner {
        gmxPositionRouter = positionRouter;
    }

    function setGmxOrderbook(IOrderBook orderBook) public onlyOwner {
        gmxOrderbook = orderBook;
    }

    function setGmxVault(IVault vault) public onlyOwner {
        gmxVault = vault;
    }

    bytes32 internal constant PERPIE_GMX_REFERRAL_CODE =
        0x7065727069650000000000000000000000000000000000000000000000000000;

    constructor(
        FeesManager _feesManager,
        IPositionRouter _gmxPositionRouter,
        IOrderBook _gmxOrderbook,
        IVault vault
    ) PerpFeesModule(_feesManager, "GMXV1") {
        gmxPositionRouter = _gmxPositionRouter;
        gmxOrderbook = _gmxOrderbook;
        gmxVault = vault;
    }

    // ====== Overrides ====== //
    function _getPrice(
        address token,
        bool isLong,
        uint256 /**sizeDelta */
    ) internal view override returns (uint256 price) {
        // This is the logic from GMX contract
        price = isLong
            ? gmxVault.getMinPrice(token)
            : gmxVault.getMaxPrice(token);
    }

    function _usdToToken(
        address token,
        uint256 usdAmount,
        uint256 price
    ) internal view override returns (uint256 tokenAmount) {
        tokenAmount = gmxVault.usdToToken(token, usdAmount, price);
    }

    // ====== Methods ====== //
    function createIncreasePosition(
        address[] memory _path,
        address _indexToken,
        uint256 _amountIn,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 /**_referralCode */,
        address _callbackTarget
    ) external payable {
        _transferMessageValue(msg.sender);
        uint256 fee;
        uint256 feeBps;
        (_sizeDelta, _amountIn, fee, feeBps) = _chargeFee(
            msg.sender,
            _path[0],
            _isLong,
            _sizeDelta,
            _amountIn
        );

        _minOut = _deductFeeBps(_minOut, feeBps);

        _execute(
            address(gmxPositionRouter),
            abi.encodeCall(
                IPositionRouter.createIncreasePosition,
                (
                    _path,
                    _indexToken,
                    _amountIn,
                    _minOut,
                    _sizeDelta,
                    _isLong,
                    _acceptablePrice,
                    _executionFee,
                    PERPIE_GMX_REFERRAL_CODE,
                    _callbackTarget
                )
            ),
            msg.value
        );
    }

    function createIncreasePositionETH(
        address[] memory _path,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        bool _isLong,
        uint256 _acceptablePrice,
        uint256 _executionFee,
        bytes32 /**_referralCode */,
        address _callbackTarget
    ) external payable {
        // We just need it for the values
        _transferMessageValue(msg.sender);

        uint256 amountIn = msg.value - _executionFee;
        uint256 fee;
        uint256 feeBps;

        (_sizeDelta, amountIn, fee, feeBps) = _chargeFee(
            msg.sender,
            _path[0],
            _isLong,
            _sizeDelta,
            amountIn,
            true
        );

        _minOut = _deductFeeBps(_minOut, feeBps);

        _execute(
            address(gmxPositionRouter),
            abi.encodeCall(
                IPositionRouter.createIncreasePositionETH,
                (
                    _path,
                    _indexToken,
                    _minOut,
                    _sizeDelta,
                    _isLong,
                    _acceptablePrice,
                    _executionFee,
                    PERPIE_GMX_REFERRAL_CODE,
                    _callbackTarget
                )
            ),
            amountIn + _executionFee
        );
    }

    function createIncreaseOrder(
        address[] memory _path,
        uint256 _amountIn,
        address _indexToken,
        uint256 _minOut,
        uint256 _sizeDelta,
        address _collateralToken,
        bool _isLong,
        uint256 _triggerPrice,
        bool _triggerAboveThreshold,
        uint256 _executionFee,
        bool _shouldWrap
    ) external payable {
        // We just need it for the values
        _transferMessageValue(msg.sender);

        uint256 feeBps;
        {
            (_sizeDelta, _amountIn, , feeBps) = _chargeFee(
                msg.sender,
                _path[0],
                _isLong,
                _sizeDelta,
                _amountIn,
                _shouldWrap
            );
        }
        _minOut = _deductFeeBps(_minOut, feeBps);

        _execute(
            address(gmxOrderbook),
            abi.encodeCall(
                IOrderBook.createIncreaseOrder,
                (
                    _path,
                    _amountIn,
                    _indexToken,
                    _minOut,
                    _sizeDelta,
                    _collateralToken,
                    _isLong,
                    _triggerPrice,
                    _triggerAboveThreshold,
                    _executionFee,
                    _shouldWrap
                )
            ),
            _shouldWrap ? _amountIn + _executionFee : msg.value
        );
    }
}

