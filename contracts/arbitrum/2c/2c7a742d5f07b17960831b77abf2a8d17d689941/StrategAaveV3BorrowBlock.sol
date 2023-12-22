// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IPool} from "./IPool.sol";
import {IAaveOracle} from "./IAaveOracle.sol";
import {DataTypes as AaveDataTypes} from "./contracts_DataTypes.sol";

import {IStrategAaveV3PositionManager} from "./IStrategAaveV3PositionManager.sol";
import {IStrategStrategyBlock} from "./IStrategStrategyBlock.sol";
import {LibBlock} from "./LibBlock.sol";
import {LibOracleState} from "./LibOracleState.sol";
import {DataTypes} from "./contracts_DataTypes.sol";

/**
 * @title Aave V3 Borrow Strateg. Block
 * @author Bliiitz
 * @notice Block to use position manager instance to borrow a token against a collateral on Aave V3
 * @custom:block-id AAVE_V3_BORROW
 * @custom:block-type position-manager
 * @custom:block-action Borrow
 * @custom:block-protocol-id AAVE_V3
 * @custom:block-protocol-name Aave v3
 * @custom:block-params-tuple tuple(address positionManager, address collateral, address dept, uint256 tokenInPercent)
 * @custom:position-manager-params-tuple tuple(bool leverageMode, address collateral, uint256 collateralDecimals, address borrowed, uint256 borrowedDecimals, uint8 eModeCategoryId, uint256 deptType, uint256 hfMin, uint256 hfMax, uint256 hfDesired)
 */
contract StrategAaveV3BorrowBlock is IStrategStrategyBlock {
    using SafeERC20 for IERC20;
    using LibOracleState for DataTypes.OracleState;

    IPool public immutable pool;
    IAaveOracle public immutable oracle;
    string public ipfsHash;

    struct BlockParameters {
        address positionManager;
        address collateral;
        address dept;
        uint256 tokenInPercent;
    }

    constructor(address _pool, address _oracle, string memory _ipfsHash) {
        pool = IPool(_pool);
        oracle = IAaveOracle(_oracle);
        ipfsHash = _ipfsHash;
    }

    function dynamicParamsInfo(
        DataTypes.BlockExecutionType _exec,
        bytes memory _params,
        DataTypes.OracleState memory _oracleData
    ) external view returns (bool, DataTypes.DynamicParamsType, bytes memory) {
        BlockParameters memory parameters = abi.decode(_params, (BlockParameters));

        if (_exec != DataTypes.BlockExecutionType.EXIT) {
            return (false, DataTypes.DynamicParamsType.PORTAL_SWAP, "");
        }

        uint256 deptTokenBal = _oracleData.findTokenAmount(parameters.dept);
        IStrategAaveV3PositionManager pm = IStrategAaveV3PositionManager(parameters.positionManager);
        IStrategAaveV3PositionManager.BorrowStatus memory status = pm.borrowStatus(true, deptTokenBal);

        DataTypes.DynamicSwapParams memory swap;
        if (status.positionDeltaIsPositive) {
            swap = DataTypes.DynamicSwapParams({
                fromToken: parameters.dept,
                toToken: parameters.collateral,
                isPercent: false,
                value: status.deltaAmount
            });
        } else {
            swap = DataTypes.DynamicSwapParams({
                fromToken: parameters.collateral,
                toToken: parameters.dept,
                isPercent: false,
                value: status.deltaAmount
            });
        }

        return (true, DataTypes.DynamicParamsType.PORTAL_SWAP, abi.encode(swap));
    }

    function enter(uint256 _index) external {
        BlockParameters memory parameters = abi.decode(LibBlock.getStrategyStorageByIndex(_index), (BlockParameters));

        uint256 collateralAmount =
            IERC20(parameters.collateral).balanceOf(address(this)) * parameters.tokenInPercent / 10000;
        IStrategAaveV3PositionManager pm = IStrategAaveV3PositionManager(parameters.positionManager);

        IERC20(parameters.collateral).safeIncreaseAllowance(address(pool), collateralAmount);
        pm.borrow(collateralAmount);
    }

    function exit(uint256 _index, uint256) external {
        BlockParameters memory parameters = abi.decode(LibBlock.getStrategyStorageByIndex(_index), (BlockParameters));

        bytes memory dynParameters = LibBlock.getDynamicBlockData(_index);

        AaveDataTypes.ReserveData memory reserveData = pool.getReserveData(parameters.dept);
        uint256 deptTokenBal = IERC20(parameters.dept).balanceOf(address(this));
        uint256 repayAmount = IERC20(reserveData.variableDebtTokenAddress).balanceOf(parameters.positionManager);

        if (repayAmount <= deptTokenBal) {
            IERC20(parameters.dept).safeTransfer(parameters.positionManager, repayAmount);
        } else {
            IERC20(parameters.dept).safeTransfer(parameters.positionManager, deptTokenBal);
        }

        IStrategAaveV3PositionManager(parameters.positionManager).repay(dynParameters);
    }

    function oracleEnter(DataTypes.OracleState memory _before, bytes memory _parameters)
        external
        view
        returns (DataTypes.OracleState memory)
    {
        BlockParameters memory parameters = abi.decode(_parameters, (BlockParameters));
        DataTypes.OracleState memory oracleState = _before;
        uint256 collateralBal = oracleState.findTokenAmount(parameters.collateral);

        uint256 amountToDeposit;
        if (collateralBal == 0) {
            collateralBal = IERC20(parameters.collateral).balanceOf(oracleState.vault);
            amountToDeposit = collateralBal * parameters.tokenInPercent / 10000;
            oracleState.addTokenAmount(parameters.collateral, collateralBal);
        } else {
            amountToDeposit = collateralBal * parameters.tokenInPercent / 10000;
        }

        uint256 borrowAmountFor =
            IStrategAaveV3PositionManager(parameters.positionManager).borrowAmountFor(amountToDeposit);

        oracleState.removeTokenAmount(parameters.collateral, amountToDeposit);
        oracleState.addTokenAmount(parameters.dept, borrowAmountFor);
        return oracleState;
    }

    function oracleExit(DataTypes.OracleState memory _before, bytes memory _parameters)
        external
        view
        returns (DataTypes.OracleState memory)
    {
        BlockParameters memory parameters = abi.decode(_parameters, (BlockParameters));
        DataTypes.OracleState memory oracleState = _before;
        uint256 deptTokenBal = oracleState.findTokenAmount(parameters.dept);

        IStrategAaveV3PositionManager pm = IStrategAaveV3PositionManager(parameters.positionManager);
        IStrategAaveV3PositionManager.Position memory position = pm.position();

        if (deptTokenBal == 0) {
            deptTokenBal = position.dept.token.balanceOf(oracleState.vault);
            oracleState.addTokenAmount(parameters.dept, deptTokenBal);
        }

        uint256 repayAmount = position.dept.deptToken.balanceOf(parameters.positionManager);

        uint256 toSendForRepay;
        if (repayAmount <= deptTokenBal) {
            toSendForRepay = repayAmount;
        } else {
            toSendForRepay = deptTokenBal;
        }

        uint256 collateralReturned =
            IStrategAaveV3PositionManager(parameters.positionManager).returnedAmountAfterRepay(toSendForRepay);

        oracleState.removeTokenAmount(parameters.dept, toSendForRepay);
        oracleState.addTokenAmount(parameters.collateral, collateralReturned);
        return oracleState;
    }
}

