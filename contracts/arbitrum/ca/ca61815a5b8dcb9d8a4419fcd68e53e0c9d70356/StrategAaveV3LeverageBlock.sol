// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

import {IPool} from "./IPool.sol";
import {IAaveOracle} from "./IAaveOracle.sol";

import {IStrategStrategyBlock} from "./IStrategStrategyBlock.sol";
import {LibBlock} from "./LibBlock.sol";
import {LibOracleState} from "./LibOracleState.sol";
import {DataTypes} from "./contracts_DataTypes.sol";

import {IStrategAaveV3PositionManager} from "./IStrategAaveV3PositionManager.sol";

/**
 * @title Aave V3 Leverage Strateg. Block
 * @author Bliiitz
 * @notice Block to leverage a token against an other on Aave V3
 * @custom:block-id AAVE_V3_LEVERAGE
 * @custom:block-type position-manager
 * @custom:block-action Leverage
 * @custom:block-protocol-id AAVE_V3
 * @custom:block-protocol-name Aave v3
 * @custom:block-params-tuple tuple(address positionManager, address collateral, address dept, uint256 tokenInPercent)
 */
contract StrategAaveV3LeverageBlock is IStrategStrategyBlock {
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
        IStrategAaveV3PositionManager pm = IStrategAaveV3PositionManager(parameters.positionManager);
        IStrategAaveV3PositionManager.Position memory position = pm.position();
        IStrategAaveV3PositionManager.LeverageStatus memory status = pm.leverageStatus();

        DataTypes.DynamicSwapParams memory swap;
        if (_exec == DataTypes.BlockExecutionType.ENTER) {
            swap = DataTypes.DynamicSwapParams({
                fromToken: parameters.dept,
                toToken: parameters.collateral,
                isPercent: false,
                value: _computeLeverageSwapAmount(_oracleData.findTokenAmount(parameters.collateral), position, status)
            });

            return (true, DataTypes.DynamicParamsType.PORTAL_SWAP, abi.encode(swap));
        }

        if (_exec == DataTypes.BlockExecutionType.EXIT) {
            swap = DataTypes.DynamicSwapParams({
                fromToken: parameters.collateral,
                toToken: parameters.dept,
                isPercent: false,
                value: _computeUnleverageSwapAmount(position, status)
            });

            return (true, DataTypes.DynamicParamsType.PORTAL_SWAP, abi.encode(swap));
        }

        return (false, DataTypes.DynamicParamsType.NONE, "");
    }

    function enter(uint256 _index) external {
        BlockParameters memory parameters = abi.decode(LibBlock.getStrategyStorageByIndex(_index), (BlockParameters));

        bytes memory dynParameters = LibBlock.getDynamicBlockData(_index);

        uint256 collateralAmount =
            IERC20(parameters.collateral).balanceOf(address(this)) * parameters.tokenInPercent / 10000;
        IStrategAaveV3PositionManager pm = IStrategAaveV3PositionManager(parameters.positionManager);

        IERC20(parameters.collateral).safeIncreaseAllowance(address(pool), collateralAmount);
        pm.leverage(collateralAmount, dynParameters);
    }

    function exit(uint256 _index, uint256) external {
        BlockParameters memory parameters = abi.decode(LibBlock.getStrategyStorageByIndex(_index), (BlockParameters));

        bytes memory dynParameters = LibBlock.getDynamicBlockData(_index);
        IStrategAaveV3PositionManager(parameters.positionManager).unleverage(dynParameters);
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

        oracleState.removeTokenAmount(parameters.collateral, amountToDeposit);
        return oracleState;
    }

    function oracleExit(DataTypes.OracleState memory _before, bytes memory _parameters)
        external
        view
        returns (DataTypes.OracleState memory)
    {
        BlockParameters memory parameters = abi.decode(_parameters, (BlockParameters));
        DataTypes.OracleState memory oracleState = _before;
        uint256 collateralReturned =
            IStrategAaveV3PositionManager(parameters.positionManager).returnedAmountAfterUnleverage();
        oracleState.addTokenAmount(parameters.collateral, collateralReturned);
        return oracleState;
    }

    function _computeLeverageSwapAmount(
        uint256 amountIn,
        IStrategAaveV3PositionManager.Position memory position,
        IStrategAaveV3PositionManager.LeverageStatus memory status
    ) internal view returns (uint256) {
        address[] memory assets = new address[](2);
        assets[0] = address(position.collateral.token);
        assets[1] = address(position.dept.token);
        uint256[] memory prices = oracle.getAssetsPrices(assets);
        uint256 totalCollateral;

        if (status.collateralAmount > 0) {
            uint256 currentCollateralUSD = prices[0] * status.collateralAmount / 10 ** position.collateral.decimals;
            uint256 currentBorrowUSD = prices[1] * status.deptAmount / 10 ** position.dept.decimals;

            uint256 estimatedInitialCollateral =
                (currentCollateralUSD - currentBorrowUSD) * 10 ** position.collateral.decimals / prices[0];
            totalCollateral = amountIn + estimatedInitialCollateral;
        } else {
            totalCollateral = amountIn;
        }

        uint256 amountInUSD = prices[0] * totalCollateral / 10 ** position.collateral.decimals;
        uint256 flashloanAmountInUSD = _computeFlashloanUSDAmountToMatchHealthfactor(
            position.collateral.lts, amountInUSD, position.healthfactor.desired
        );

        uint256 flashloanAmount = flashloanAmountInUSD * 10 ** position.dept.decimals / prices[1];
        flashloanAmount = flashloanAmount - status.deptAmount;
        return flashloanAmount;
    }

    function _computeUnleverageSwapAmount(
        IStrategAaveV3PositionManager.Position memory position,
        IStrategAaveV3PositionManager.LeverageStatus memory status
    ) internal view returns (uint256) {
        address[] memory assets = new address[](2);
        assets[0] = address(position.collateral.token);
        assets[1] = address(position.dept.token);
        uint256[] memory prices = oracle.getAssetsPrices(assets);

        uint256 deptInUSD = prices[1] * status.deptAmount / 10 ** position.dept.decimals;
        uint256 estimatedCollateralFlashloanToRepay = deptInUSD * 10 ** position.collateral.decimals / prices[0];
        uint256 flashloanAmount = estimatedCollateralFlashloanToRepay * 103 / 100;

        return flashloanAmount;
    }

    function _computeFlashloanUSDAmountToMatchHealthfactor(
        uint256 lts,
        uint256 initialCollateralAmount,
        uint256 hfDesired
    ) internal pure returns (uint256) {
        bool ended;
        uint256 initialBorrowAmount = (initialCollateralAmount * lts * 1e18 / 10000) / hfDesired;

        uint256 totalCollateral = initialCollateralAmount;
        uint256 totalBorrow = initialBorrowAmount;
        uint256 previousBorrow = initialBorrowAmount;
        uint256 previousCumulated = initialBorrowAmount;

        while (!ended) {
            totalCollateral = totalCollateral + previousBorrow;
            totalBorrow = (totalCollateral * lts * 1e18 / 10000) / hfDesired;
            previousBorrow = totalBorrow - previousCumulated;
            previousCumulated = previousCumulated + previousBorrow;

            if (previousBorrow <= initialCollateralAmount * 100 / 10000) {
                ended = true;
            }
        }

        return totalBorrow;
    }
}

