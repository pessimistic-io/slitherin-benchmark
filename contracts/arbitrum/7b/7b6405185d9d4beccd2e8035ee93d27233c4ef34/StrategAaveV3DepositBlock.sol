// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IPool} from "./IPool.sol";
import {IAaveOracle} from "./IAaveOracle.sol";
import {DataTypes as AaveDataTypes} from "./contracts_DataTypes.sol";
import {IStrategStrategyBlock} from "./IStrategStrategyBlock.sol";
import {LibBlock} from "./LibBlock.sol";
import {DataTypes} from "./contracts_DataTypes.sol";
import {LibOracleState} from "./LibOracleState.sol";

/**
 * @title Aave V3 Deposit Strateg. Block
 * @author Bliiitz
 * @notice Block to deposit a token on Aave V3
 * @custom:block-id AAVE_V3_DEPOSIT
 * @custom:block-type block
 * @custom:block-action Deposit
 * @custom:block-protocol-id AAVE_V3
 * @custom:block-protocol-name Aave v3
 * @custom:block-params-tuple tuple(uint256 tokenInPercent, address token)
 */
contract StrategAaveV3DepositBlock is IStrategStrategyBlock {
    using SafeERC20 for IERC20;
    using LibOracleState for DataTypes.OracleState;

    uint16 constant REFERAL = 57547;

    IPool public immutable pool;
    IAaveOracle public immutable oracle;
    string public ipfsHash;

    struct BlockParameters {
        uint256 tokenInPercent;
        address token;
    }

    constructor(address _pool, address _oracle, string memory _ipfsHash) {
        pool = IPool(_pool);
        oracle = IAaveOracle(_oracle);
        ipfsHash = _ipfsHash;
    }

    function dynamicParamsInfo(DataTypes.BlockExecutionType, bytes memory, DataTypes.OracleState memory)
        external
        pure
        returns (bool, DataTypes.DynamicParamsType, bytes memory)
    {
        return (false, DataTypes.DynamicParamsType.NONE, "");
    }

    function enter(uint256 _index) external {
        BlockParameters memory parameters = abi.decode(LibBlock.getStrategyStorageByIndex(_index), (BlockParameters));

        uint256 amountToDeposit = IERC20(parameters.token).balanceOf(address(this)) * parameters.tokenInPercent / 10000;

        IERC20(parameters.token).safeIncreaseAllowance(address(pool), amountToDeposit);
        pool.supply(parameters.token, amountToDeposit, address(this), REFERAL);
    }

    function exit(uint256 _index, uint256 _percent) external {
        BlockParameters memory parameters = abi.decode(LibBlock.getStrategyStorageByIndex(_index), (BlockParameters));

        AaveDataTypes.ReserveData memory collateralReserveData = pool.getReserveData(parameters.token);
        uint256 amountToWithdraw =
            IERC20(collateralReserveData.aTokenAddress).balanceOf(address(this)) * _percent / 10000;
        pool.withdraw(parameters.token, amountToWithdraw, address(this));
    }

    function oracleEnter(DataTypes.OracleState memory _before, bytes memory _parameters)
        external
        view
        returns (DataTypes.OracleState memory)
    {
        BlockParameters memory parameters = abi.decode(_parameters, (BlockParameters));
        DataTypes.OracleState memory oracleState = _before;
        uint256 amountToDeposit = oracleState.findTokenAmount(parameters.token) * parameters.tokenInPercent / 10000;

        if (amountToDeposit == 0) {
            amountToDeposit = IERC20(parameters.token).balanceOf(oracleState.vault);
            oracleState.addTokenAmount(parameters.token, amountToDeposit);
        }

        AaveDataTypes.ReserveData memory collateralReserveData = pool.getReserveData(parameters.token);
        oracleState.removeTokenAmount(parameters.token, amountToDeposit);
        oracleState.addTokenAmount(collateralReserveData.aTokenAddress, amountToDeposit);
        return oracleState;
    }

    function oracleExit(DataTypes.OracleState memory _before, bytes memory _parameters)
        external
        view
        returns (DataTypes.OracleState memory)
    {
        BlockParameters memory parameters = abi.decode(_parameters, (BlockParameters));
        DataTypes.OracleState memory oracleState = _before;

        AaveDataTypes.ReserveData memory collateralReserveData = pool.getReserveData(parameters.token);
        uint256 amountToWithdraw = oracleState.findTokenAmount(collateralReserveData.aTokenAddress);

        if (amountToWithdraw == 0) {
            amountToWithdraw = IERC20(collateralReserveData.aTokenAddress).balanceOf(oracleState.vault);
            oracleState.addTokenAmount(collateralReserveData.aTokenAddress, amountToWithdraw);
        }

        oracleState.removeTokenAmount(collateralReserveData.aTokenAddress, amountToWithdraw);
        oracleState.addTokenAmount(parameters.token, amountToWithdraw);
        return oracleState;
    }
}

