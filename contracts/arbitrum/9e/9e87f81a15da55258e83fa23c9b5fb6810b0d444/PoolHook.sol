// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.18;

import {Ownable2Step} from "./Ownable2Step.sol";
import {IPoolHook} from "./IPoolHook.sol";
import {IPoolWithStorage} from "./IPoolWithStorage.sol";
import {IMintableErc20} from "./IMintableErc20.sol";
import {ILevelOracle} from "./ILevelOracle.sol";
import {ITradingContest} from "./ITradingContest.sol";
import {ITradingIncentiveController} from "./ITradingIncentiveController.sol";
import {IReferralController} from "./IReferralController.sol";
import {DataTypes} from "./DataTypes.sol";

contract PoolHook is IPoolHook {
    uint8 constant lyLevelDecimals = 18;
    uint256 constant VALUE_PRECISION = 1e30;

    address private immutable pool;
    IMintableErc20 public immutable lyLevel;

    IReferralController immutable referralController;
    ITradingContest immutable tradingContest;
    ITradingIncentiveController immutable tradingIncentiveController;

    constructor(
        address _lyLevel,
        address _pool,
        address _referralController,
        address _tradingIncentiveController,
        address _tradingContest
    ) {
        if (_lyLevel == address(0)) revert InvalidAddress();
        if (_pool == address(0)) revert InvalidAddress();
        if (_referralController == address(0)) revert InvalidAddress();
        if (_tradingContest == address(0)) revert InvalidAddress();
        if (_tradingIncentiveController == address(0)) revert InvalidAddress();

        lyLevel = IMintableErc20(_lyLevel);
        pool = _pool;
        referralController = IReferralController(_referralController);
        tradingIncentiveController = ITradingIncentiveController(_tradingIncentiveController);
        tradingContest = ITradingContest(_tradingContest);
    }

    modifier onlyPool() {
        _validatePool(msg.sender);
        _;
    }

    /**
     * @inheritdoc IPoolHook
     */
    function postIncreasePosition(
        address _owner,
        address _indexToken,
        address _collateralToken,
        DataTypes.Side _side,
        bytes calldata _extradata
    ) external onlyPool {
        (,, uint256 _feeValue) = abi.decode(_extradata, (uint256, uint256, uint256));
        _updateReferralData(_owner, _feeValue);
        _sentTradingRecord(_owner, _feeValue);
        emit PostIncreasePositionExecuted(pool, _owner, _indexToken, _collateralToken, _side, _extradata);
    }

    /**
     * @inheritdoc IPoolHook
     */
    function postDecreasePosition(
        address _owner,
        address _indexToken,
        address _collateralToken,
        DataTypes.Side _side,
        bytes calldata _extradata
    ) external onlyPool {
        ( /*uint256 sizeChange*/ , /* uint256 collateralValue */, uint256 _feeValue) =
            abi.decode(_extradata, (uint256, uint256, uint256));
        _updateReferralData(_owner, _feeValue);
        _sentTradingRecord(_owner, _feeValue);
        emit PostDecreasePositionExecuted(msg.sender, _owner, _indexToken, _collateralToken, _side, _extradata);
    }

    /**
     * @inheritdoc IPoolHook
     */
    function postLiquidatePosition(
        address _owner,
        address _indexToken,
        address _collateralToken,
        DataTypes.Side _side,
        bytes calldata _extradata
    ) external onlyPool {
        ( /*uint256 sizeChange*/ , /* uint256 collateralValue */, uint256 _feeValue) =
            abi.decode(_extradata, (uint256, uint256, uint256));
        _updateReferralData(_owner, _feeValue);
        _sentTradingRecord(_owner, _feeValue);
        emit PostLiquidatePositionExecuted(msg.sender, _owner, _indexToken, _collateralToken, _side, _extradata);
    }

    /**
     * @inheritdoc IPoolHook
     */
    function postSwap(address _user, address _tokenIn, address _tokenOut, bytes calldata _data) external onlyPool {
        ( /*uint256 amountIn*/ , /* uint256 amountOut */, uint256 feeValue, bytes memory extradata) =
            abi.decode(_data, (uint256, uint256, uint256, bytes));
        (address benificier) = extradata.length != 0 ? abi.decode(extradata, (address)) : (address(0));
        benificier = benificier == address(0) ? _user : benificier;
        _updateReferralData(benificier, feeValue);
        _sentTradingRecord(benificier, feeValue);
        emit PostSwapExecuted(msg.sender, _user, _tokenIn, _tokenOut, _data);
    }

    // ========= Admin function ========

    function _updateReferralData(address _trader, uint256 _value) internal {
        if (address(referralController) != address(0) && _trader != address(0)) {
            referralController.updateFee(_trader, _value);
        }
    }

    function _sentTradingRecord(address _trader, uint256 _value) internal {
        if (_value == 0 || _trader == address(0)) {
            return;
        }

        if (address(tradingIncentiveController) != address(0)) {
            tradingIncentiveController.record(_value);
        }

        if (address(tradingContest) != address(0)) {
            tradingContest.record(_trader, _value);
        }

        uint256 _lyTokenAmount = (_value * 10 ** lyLevelDecimals) / VALUE_PRECISION;
        lyLevel.mint(_trader, _lyTokenAmount);
    }

    function _validatePool(address sender) internal view {
        if (sender != pool) {
            revert OnlyPool();
        }
    }

    event ReferralControllerSet(address controller);
    event TradingIncentiveSet(address tradingRecord, address tradingIncentiveController);

    error InvalidAddress();
    error OnlyPool();
}

