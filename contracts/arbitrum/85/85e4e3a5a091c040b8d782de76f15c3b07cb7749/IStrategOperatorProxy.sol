// // SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./SafeERC20.sol";

import {IStrategOperatingPaymentToken} from "./IStrategOperatingPaymentToken.sol";
import {IStrategVault} from "./IStrategVault.sol";
import {IStrategStrategyBlock} from "./interfaces_IStrategStrategyBlock.sol";
import {DataTypes} from "./DataTypes.sol";

error VaultRebalanceReverted(bytes data);
error PositionManagerOperationReverted(bytes data);
error BufferIsOverLimit();
error BufferIsUnderLimit();

/**
 * @title StrategOperatorProxy
 * @author Bliiitz
 * @notice This contract serves as a proxy for executing operations on strategy vaults. It requires the OPERATOR_ROLE to perform the operations.
 */
interface IStrategOperatorProxy {
    enum StrategyState {
        Started,
        Stopped
    }

    struct StrategVaultInfo {
        address owner;
        address asset;
        uint256 totalSupply;
        uint256 totalAssets;
        uint256 gasAvailable;
        uint256 bufferAssetsAvailable;
        uint256 bufferSize;
        uint256 bufferDerivation;
        uint256 lastHarvestIndex;
        uint256 currentVaultIndex;
        uint256 harvestFee;
        uint256 creatorFee;
        uint256 minSupplyForActivation;
        uint256 onHarvestNativeAssetReceived;
        uint256 middleware;
    }

    struct StrategyBlockExecutionInfo {
        bool dynParamsNeeded;
        DataTypes.DynamicParamsType dynParamsType;
        bytes dynParamsInfo;
        address blockAddr;
        DataTypes.OracleState oracleStatus;
    }

    struct StrategVaultExecutionInfo {
        uint256 blocksLength;
        DataTypes.OracleState startOracleStatus;
        StrategyBlockExecutionInfo[] blocksInfo;
    }

    struct StrategVaultHarvestExecutionInfo {
        uint256 blocksLength;
        uint256 receivedAmount;
        DataTypes.OracleState startOracleStatus;
        StrategyBlockExecutionInfo[] blocksInfo;
    }

    struct StrategWithdrawalRebalanceExecutionInfo {
        uint256 blocksLength;
        uint256 receivedAmount;
        DataTypes.OracleState startOracleStatusExit;
        StrategyBlockExecutionInfo[] blocksInfoExit;
        DataTypes.OracleState startOracleStatusEnter;
        StrategyBlockExecutionInfo[] blocksInfoEnter;
    }

    event VaultStrategyStateChanged(address vault, StrategyState state);

    /**
     * @dev Return strategy enter execution information for a specific vault
     * @param _vault vault address
     */
    function getPartialVaultStrategyEnterExecutionInfo(address _vault, uint256 _from, DataTypes.OracleState memory _tmp)
        external
        view
        returns (StrategVaultExecutionInfo memory info);

    /**
     * @dev Return strategy exit execution information for a specific vault
     * @param _vault vault address
     */
    function getPartialVaultStrategyExitExecutionInfo(address _vault, uint256 _to)
        external
        view
        returns (StrategVaultExecutionInfo memory info);

    /**
     * @dev Return strategy enter execution information for a specific vault
     * @param _vault vault address
     */
    function getVaultStrategyEnterExecutionInfo(address _vault)
        external
        view
        returns (StrategVaultExecutionInfo memory info);

    /**
     * @dev Return strategy exit execution information for a specific vault
     * @param _vault vault address
     */
    function getVaultStrategyExitExecutionInfo(address _vault)
        external
        view
        returns (StrategVaultExecutionInfo memory info);

    /**
     * @dev Return strategy harvest execution information for a specific vault
     * @param _vault vault address
     */
    function getVaultHarvestExecutionInfo(address _vault)
        external
        returns (StrategVaultHarvestExecutionInfo memory info);

    /**
     * @dev Return vault's strategy configuration and informations
     * @param _vault vault address
     */
    function vaultInfo(address _vault) external returns (StrategVaultInfo memory status);

    function vaultStopStrategy(
        address _vault,
        address _payer,
        uint256 _gasCost,
        uint256[] memory _dynParamsIndex,
        bytes[] memory _dynParams
    ) external;

    function vaultHarvest(
        address _vault,
        address _payer,
        uint256 _gasCost,
        uint256[] memory _dynParamsIndex,
        bytes[] memory _dynParams,
        bytes memory _portalPayload
    ) external;

    function vaultRebalance(
        address _vault,
        address _payer,
        uint256 _gasCost,
        uint256[] memory _dynParamsIndexEnter,
        bytes[] memory _dynParamsEnter,
        uint256[] memory _dynParamsIndexExit,
        bytes[] memory _dynParamsExit
    ) external;

    function positionManagerOperation(
        address _positionManager,
        address _payer,
        uint256 _gasCost,
        bytes calldata _payload
    ) external;

    function vaultWithdrawalRebalance(
        address _vault,
        uint256 _gasCost,
        bytes memory _gasCostPermitParams,
        address _user,
        uint256 _amount,
        bytes memory _swapParams,
        bytes memory _permitParams,
        uint256[] memory _dynParamsIndexEnter,
        bytes[] memory _dynParamsEnter,
        uint256[] memory _dynParamsIndexExit,
        bytes[] memory _dynParamsExit
    ) external;

    function withdrawFees(address[] memory _tokens) external;
}

