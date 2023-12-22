// // SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./SafeERC20.sol";

import {IStrategOperatingPaymentToken} from "./IStrategOperatingPaymentToken.sol";
import {IStrategPositionManager} from "./IStrategPositionManager.sol";
import {IStrategVault} from "./IStrategVault.sol";
import {IStrategOperatorProxy} from "./IStrategOperatorProxy.sol";
import {IStrategPortal} from "./IStrategPortal.sol";
import {IStrategStrategyBlock} from "./interfaces_IStrategStrategyBlock.sol";
import {IStrategHarvestBlock} from "./IStrategHarvestBlock.sol";
import {IStrategCommonBlock} from "./interfaces_IStrategCommonBlock.sol";
import {LibPermit} from "./LibPermit.sol";
import {LibBlock} from "./LibBlock.sol";
import {LibOracleState} from "./LibOracleState.sol";
import {VaultConfiguration} from "./VaultConfiguration.sol";
import {DataTypes} from "./DataTypes.sol";

error VaultRebalanceReverted(bytes data);
error PositionManagerOperationReverted(bytes data);
error BufferIsOverLimit();
error BufferIsUnderLimit();
error PortalExecutionFailed(bytes data);

/**
 * @title StrategOperatorProxy
 * @author Bliiitz
 * @notice This contract serves as a proxy for executing operations on strategy vaults. It requires the OPERATOR_ROLE to perform the operations.
 */
contract StrategOperatorProxy is Initializable, AccessControlUpgradeable, IStrategOperatorProxy {
    using SafeERC20 for IERC20;
    using VaultConfiguration for DataTypes.VaultConfigurationMap;
    using LibOracleState for DataTypes.OracleState;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    IStrategOperatingPaymentToken public paymentToken;
    IStrategPortal public portal;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract by granting the DEFAULT_ADMIN_ROLE to the treasury address.
     * @param _treasury The address of the treasury.
     */
    function initialize(address _treasury) public initializer {
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _treasury);
    }

    function setPaymentToken(address _paymentToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        paymentToken = IStrategOperatingPaymentToken(_paymentToken);
    }

    function setPortal(address _portal) external onlyRole(DEFAULT_ADMIN_ROLE) {
        portal = IStrategPortal(_portal);
    }

    /**
     * @notice Executes the harvest function on the strategy vault.
     * @param _vault Address of the strategy vault.
     * @param _payer payer for operation cost
     * @param _gasCost gas cost to pay for operation
     * @param _dynParamsIndex Array of dynamic parameter indexes.
     * @param _dynParams Array of dynamic parameters.
     */
    function vaultStopStrategy(
        address _vault,
        address _payer,
        uint256 _gasCost,
        uint256[] memory _dynParamsIndex,
        bytes[] memory _dynParams
    ) external onlyRole(OPERATOR_ROLE) {
        if (_gasCost > 0) {
            if (_payer == address(0)) {
                paymentToken.executePayment(_vault, msg.sender, _gasCost);
            } else {
                paymentToken.executePaymentFrom(_payer, _vault, msg.sender, _gasCost);
            }
        }

        IStrategVault(_vault).stopStrategy(_dynParamsIndex, _dynParams);
    }

    /**
     * @notice Executes the harvest function on the strategy vault.
     * @param _vault Address of the strategy vault.
     * @param _payer payer for operation cost
     * @param _gasCost gas cost to pay for operation
     * @param _dynParamsIndex Array of dynamic parameter indexes.
     * @param _dynParams Array of dynamic parameters.
     */
    function vaultHarvest(
        address _vault,
        address _payer,
        uint256 _gasCost,
        uint256[] memory _dynParamsIndex,
        bytes[] memory _dynParams,
        bytes memory _portalPayload
    ) external onlyRole(OPERATOR_ROLE) {
        if (_gasCost > 0) {
            if (_payer == address(0)) {
                paymentToken.executePayment(_vault, msg.sender, _gasCost);
            } else {
                paymentToken.executePaymentFrom(_payer, _vault, msg.sender, _gasCost);
            }
        }

        IStrategVault(_vault).harvest(_dynParamsIndex, _dynParams);

        if (_portalPayload.length > 0) {
            IERC20 asset = IERC20(IStrategVault(_vault).asset());
            IERC20(address(asset)).safeIncreaseAllowance(address(portal), asset.balanceOf(address(this)));
            (bool success, bytes memory _data) = address(portal).call(_portalPayload);
            if (!success) revert PortalExecutionFailed(_data);
        }
    }

    /**
     * @notice Executes the rebalance function on the strategy vault.
     * @param _vault Address of the strategy vault.
     * @param _payer payer for operation cost
     * @param _gasCost gas cost to pay for operation
     * @param _dynParamsIndexEnter Array of dynamic parameter indexes for entering positions.
     * @param _dynParamsEnter Array of dynamic parameters for entering positions.
     * @param _dynParamsIndexExit Array of dynamic parameter indexes for exiting positions.
     * @param _dynParamsExit Array of dynamic parameters for exiting positions.
     */
    function vaultRebalance(
        address _vault,
        address _payer,
        uint256 _gasCost,
        uint256[] memory _dynParamsIndexEnter,
        bytes[] memory _dynParamsEnter,
        uint256[] memory _dynParamsIndexExit,
        bytes[] memory _dynParamsExit
    ) external onlyRole(OPERATOR_ROLE) {
        if (_gasCost > 0) {
            if (_payer == address(0)) {
                paymentToken.executePayment(_vault, msg.sender, _gasCost);
            } else {
                paymentToken.executePaymentFrom(_payer, _vault, msg.sender, _gasCost);
            }
        }

        IStrategVault(_vault).rebalance(_dynParamsIndexEnter, _dynParamsEnter, _dynParamsIndexExit, _dynParamsExit);
    }

    /**
     * @notice Executes the rebalance function on the position manager.
     * @param _positionManager Address of the position manager.
     * @param _payer payer for operation cost
     * @param _gasCost gas cost to pay for operation
     * @param _payload Array of dynamic parameter indexes for exiting positions.
     */
    function positionManagerOperation(
        address _positionManager,
        address _payer,
        uint256 _gasCost,
        bytes calldata _payload
    ) external onlyRole(OPERATOR_ROLE) {
        address vault = IStrategPositionManager(_positionManager).owner();

        if (_gasCost > 0) {
            if (_payer == address(0)) {
                paymentToken.executePayment(vault, msg.sender, _gasCost);
            } else {
                paymentToken.executePaymentFrom(_payer, vault, msg.sender, _gasCost);
            }
        }

        (bool success, bytes memory _data) = _positionManager.call(_payload);
        if (!success) revert PositionManagerOperationReverted(_data);
    }

    /**
     * @notice Executes price updates on portal oracle.
     * @param _addresses Addresses of tokens.
     * @param _prices related prices
     */
    function oracleUpdateOperation(address[] calldata _addresses, uint256[] calldata _prices)
        external
        onlyRole(OPERATOR_ROLE)
    {
        portal.updateOraclePrice(_addresses, _prices);
    }

    /**
     * @notice Executes the withdrawalRebalance function on the strategy vault.
     * @param _vault Address of the strategy vault.
     * @param _gasCost payer for operation cost
     * @param _gasCostPermitParams permit data to pay for operation
     * @param _user Address of the user performing the withdrawal.
     * @param _amount Amount to be withdrawn.
     * @param _portalPayload Parameters for executing a swap with returned assets.
     * @param _permitParams Parameters for executing a permit (optional).
     * @param _dynParamsIndexEnter Array of dynamic parameter indexes for entering positions.
     * @param _dynParamsEnter Array of dynamic parameters for entering positions.
     * @param _dynParamsIndexExit Array of dynamic parameter indexes for exiting positions.
     * @param _dynParamsExit Array of dynamic parameters for exiting positions.
     */
    function vaultWithdrawalRebalance(
        address _vault,
        uint256 _gasCost,
        bytes memory _gasCostPermitParams,
        address _user,
        uint256 _amount,
        bytes memory _portalPayload,
        bytes memory _permitParams,
        uint256[] memory _dynParamsIndexEnter,
        bytes[] memory _dynParamsEnter,
        uint256[] memory _dynParamsIndexExit,
        bytes[] memory _dynParamsExit
    ) external onlyRole(OPERATOR_ROLE) {
        if (_gasCost > 0) {
            if (_gasCostPermitParams.length != 0) {
                LibPermit.executePermit(address(paymentToken), _user, _gasCost, _gasCostPermitParams);
            }

            IERC20(address(paymentToken)).safeTransferFrom(_user, address(this), _gasCost);
            paymentToken.burn(msg.sender, _gasCost);
        }

        if (_permitParams.length != 0) {
            LibPermit.executePermit(_vault, _user, _amount, _permitParams);
        }

        IERC20(_vault).safeTransferFrom(_user, address(this), _amount);

        if (_portalPayload.length > 0) {
            IStrategVault(_vault).withdrawalRebalance(
                address(this), _amount, _dynParamsIndexEnter, _dynParamsEnter, _dynParamsIndexExit, _dynParamsExit
            );

            IERC20 asset = IERC20(IStrategVault(_vault).asset());

            IERC20(address(asset)).safeIncreaseAllowance(address(portal), asset.balanceOf(address(this)));

            (bool success, bytes memory _data) = address(portal).call(_portalPayload);
            if (!success) revert PortalExecutionFailed(_data);
        } else {
            IStrategVault(_vault).withdrawalRebalance(
                _user, _amount, _dynParamsIndexEnter, _dynParamsEnter, _dynParamsIndexExit, _dynParamsExit
            );
        }
    }

    /**
     * @notice Withdraws fees from the contract and transfers them to the caller.
     * @param _tokens Array of token addresses to withdraw fees from.
     */
    function withdrawFees(address[] memory _tokens) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 tLength = _tokens.length;
        for (uint256 i = 0; i < tLength; i++) {
            uint256 bal = IERC20(_tokens[i]).balanceOf(address(this));
            if (bal > 0) IERC20(_tokens[i]).safeTransfer(msg.sender, bal);
        }
    }

    /**
     * @dev Return strategy enter execution information for a specific vault
     * @param _vault vault address
     */
    function getPartialVaultStrategyEnterExecutionInfo(address _vault, uint256 _from, DataTypes.OracleState memory _tmp)
        public
        view
        returns (StrategVaultExecutionInfo memory info)
    {
        DataTypes.VaultConfigurationMap memory config = IStrategVault(_vault).configuration();
        IStrategVault vault = IStrategVault(_vault);

        (address[] memory _strategyBlocks, bytes[] memory _strategyBlocksParameters,,) = vault.getStrat();
        uint256 strategyBlocksLength = config.getStrategyBlocksLength();

        info.blocksLength = strategyBlocksLength;
        info.startOracleStatus = _tmp;
        info.blocksInfo = new StrategyBlockExecutionInfo[](
            strategyBlocksLength
        );
        for (uint256 i = _from; i < strategyBlocksLength; i++) {
            _tmp = IStrategStrategyBlock(_strategyBlocks[i]).oracleEnter(_tmp, _strategyBlocksParameters[i]);
            (bool dynParamsNeeded, DataTypes.DynamicParamsType dynParamsType, bytes memory dynParamsInfo) =
            IStrategStrategyBlock(_strategyBlocks[i]).dynamicParamsInfo(
                DataTypes.BlockExecutionType.ENTER, _strategyBlocksParameters[i], _tmp
            );

            info.blocksInfo[i] = StrategyBlockExecutionInfo({
                oracleStatus: _tmp,
                blockAddr: _strategyBlocks[i],
                dynParamsNeeded: dynParamsNeeded,
                dynParamsType: dynParamsType,
                dynParamsInfo: dynParamsInfo
            });
        }
    }

    /**
     * @dev Return strategy exit execution information for a specific vault
     * @param _vault vault address
     */
    function getPartialVaultStrategyExitExecutionInfo(address _vault, uint256 _to)
        public
        view
        returns (StrategVaultExecutionInfo memory info)
    {
        DataTypes.VaultConfigurationMap memory config = IStrategVault(_vault).configuration();
        IStrategVault vault = IStrategVault(_vault);

        (address[] memory _strategyBlocks, bytes[] memory _strategyBlocksParameters,,) = vault.getStrat();
        uint256 strategyBlocksLength = config.getStrategyBlocksLength();

        DataTypes.OracleState memory _tmp;
        _tmp.vault = address(_vault);

        info.startOracleStatus = _tmp;
        info.blocksLength = strategyBlocksLength;
        info.blocksInfo = new StrategyBlockExecutionInfo[](
            strategyBlocksLength
        );

        uint256 revertedIndex = strategyBlocksLength - 1;
        uint256 index = strategyBlocksLength - 1;
        for (uint256 i = 0; index >= _to; i++) {
            index = revertedIndex - i;

            _tmp = IStrategStrategyBlock(_strategyBlocks[index]).oracleExit(_tmp, _strategyBlocksParameters[index]);
            (bool dynParamsNeeded, DataTypes.DynamicParamsType dynParamsType, bytes memory dynParamsInfo) =
            IStrategStrategyBlock(_strategyBlocks[index]).dynamicParamsInfo(
                DataTypes.BlockExecutionType.EXIT, _strategyBlocksParameters[index], _tmp
            );

            info.blocksInfo[index] = StrategyBlockExecutionInfo({
                oracleStatus: _tmp,
                blockAddr: _strategyBlocks[index],
                dynParamsNeeded: dynParamsNeeded,
                dynParamsType: dynParamsType,
                dynParamsInfo: dynParamsInfo
            });
        }
    }

    /**
     * @dev Return strategy enter execution information for a specific vault
     * @param _vault vault address
     */
    function getVaultStrategyEnterExecutionInfo(address _vault)
        external
        view
        returns (StrategVaultExecutionInfo memory info)
    {
        DataTypes.VaultConfigurationMap memory config = IStrategVault(_vault).configuration();
        IStrategVault vault = IStrategVault(_vault);

        (address[] memory _strategyBlocks, bytes[] memory _strategyBlocksParameters,,) = vault.getStrat();
        uint256 strategyBlocksLength = config.getStrategyBlocksLength();

        if (strategyBlocksLength == 0) return info;

        DataTypes.OracleState memory _tmp;
        _tmp.vault = address(_vault);
        _tmp.tokens = new address[](1);
        _tmp.tokensAmount = new uint256[](1);

        address asset = vault.asset();
        uint256 nativeTVL = vault.totalAssets();
        uint256 availableAssets =
            IERC20(asset).balanceOf(address(vault)) + IERC20(asset).allowance(vault.buffer(), address(vault));
        uint256 desiredBuffer = (config.getBufferSize() * nativeTVL) / 10000;

        if (desiredBuffer >= availableAssets) revert BufferIsUnderLimit();

        _tmp.tokens[0] = asset;
        _tmp.tokensAmount[0] = availableAssets - desiredBuffer;

        info.startOracleStatus = _tmp;

        info.blocksLength = strategyBlocksLength;
        info.blocksInfo = new StrategyBlockExecutionInfo[](
            strategyBlocksLength
        );
        for (uint256 i = 0; i < strategyBlocksLength; i++) {
            (bool dynParamsNeeded, DataTypes.DynamicParamsType dynParamsType, bytes memory dynParamsInfo) =
            IStrategStrategyBlock(_strategyBlocks[i]).dynamicParamsInfo(
                DataTypes.BlockExecutionType.ENTER, _strategyBlocksParameters[i], _tmp
            );

            _tmp = IStrategStrategyBlock(_strategyBlocks[i]).oracleEnter(_tmp, _strategyBlocksParameters[i]);

            info.blocksInfo[i] = StrategyBlockExecutionInfo({
                oracleStatus: _tmp,
                blockAddr: _strategyBlocks[i],
                dynParamsNeeded: dynParamsNeeded,
                dynParamsType: dynParamsType,
                dynParamsInfo: dynParamsInfo
            });
        }
    }

    /**
     * @dev Return strategy exit execution information for a specific vault
     * @param _vault vault address
     */
    function getVaultWithdrawalRebalanceExecutionInfo(address _vault, uint256 _shares)
        external
        view
        returns (StrategWithdrawalRebalanceExecutionInfo memory info)
    {
        DataTypes.VaultConfigurationMap memory config = IStrategVault(_vault).configuration();
        IStrategVault vault = IStrategVault(_vault);
        address asset = vault.asset();
        (address[] memory _strategyBlocks, bytes[] memory _strategyBlocksParameters,,) = vault.getStrat();
        uint256 withdrawalPercent = (_shares * 10000) / vault.totalSupply();
        //info.receivedAmount = (withdrawalPercent * vault.totalAssets()) / 10000;

        info.receivedAmount = ((_shares * vault.totalAssets()) / vault.totalSupply());

        DataTypes.OracleState memory oracleState;
        {
            if (config.getStrategyBlocksLength() == 0) return info;

            oracleState.vault = address(_vault);

            info.startOracleStatusExit = oracleState;
            info.blocksLength = config.getStrategyBlocksLength();
            info.blocksInfoExit = new StrategyBlockExecutionInfo[](
                config.getStrategyBlocksLength()
            );

            if (config.getStrategyBlocksLength() == 1) {
                oracleState =
                    IStrategStrategyBlock(_strategyBlocks[0]).oracleExit(oracleState, _strategyBlocksParameters[0]);
                oracleState.removeAllTokenPercent(withdrawalPercent);
                (bool dynParamsNeeded, DataTypes.DynamicParamsType dynParamsType, bytes memory dynParamsInfo) =
                IStrategStrategyBlock(_strategyBlocks[0]).dynamicParamsInfo(
                    DataTypes.BlockExecutionType.EXIT, _strategyBlocksParameters[0], oracleState
                );
                info.blocksInfoExit[0] = StrategyBlockExecutionInfo({
                    oracleStatus: oracleState,
                    blockAddr: _strategyBlocks[0],
                    dynParamsNeeded: dynParamsNeeded,
                    dynParamsType: dynParamsType,
                    dynParamsInfo: dynParamsInfo
                });
            } else {
                uint256 revertedIndex = config.getStrategyBlocksLength() - 1;
                for (uint256 i = 0; i < config.getStrategyBlocksLength(); i++) {
                    uint256 index = revertedIndex - i;

                    oracleState = IStrategStrategyBlock(_strategyBlocks[index]).oracleExit(
                        oracleState, _strategyBlocksParameters[index]
                    );
                    if (i == 0) {
                        oracleState.removeAllTokenPercent(withdrawalPercent);
                    }

                    (bool dynParamsNeeded, DataTypes.DynamicParamsType dynParamsType, bytes memory dynParamsInfo) =
                    IStrategStrategyBlock(_strategyBlocks[index]).dynamicParamsInfo(
                        DataTypes.BlockExecutionType.EXIT, _strategyBlocksParameters[index], oracleState
                    );

                    info.blocksInfoExit[index] = StrategyBlockExecutionInfo({
                        oracleStatus: oracleState,
                        blockAddr: _strategyBlocks[index],
                        dynParamsNeeded: dynParamsNeeded,
                        dynParamsType: dynParamsType,
                        dynParamsInfo: dynParamsInfo
                    });
                }
            }
        }

        uint256 availableAssetsAfterWithdraw = IERC20(asset).balanceOf(address(vault))
            + IERC20(asset).allowance(vault.buffer(), address(vault)) + oracleState.findTokenAmount(asset)
            - info.receivedAmount;
        if (withdrawalPercent < 10000) {
            uint256 desiredBuffer = (
                config.getBufferSize() * (availableAssetsAfterWithdraw + vault.totalAssets() - info.receivedAmount)
            ) / 10000;

            if (desiredBuffer < availableAssetsAfterWithdraw) {
                oracleState.setTokenAmount(asset, availableAssetsAfterWithdraw - desiredBuffer);

                info.startOracleStatusEnter = oracleState;
                info.blocksLength = config.getStrategyBlocksLength();
                info.blocksInfoEnter = new StrategyBlockExecutionInfo[](
                    config.getStrategyBlocksLength()
                );
                for (uint256 i = 0; i < config.getStrategyBlocksLength(); i++) {
                    oracleState =
                        IStrategStrategyBlock(_strategyBlocks[i]).oracleEnter(oracleState, _strategyBlocksParameters[i]);
                    (bool dynParamsNeeded, DataTypes.DynamicParamsType dynParamsType, bytes memory dynParamsInfo) =
                    IStrategStrategyBlock(_strategyBlocks[i]).dynamicParamsInfo(
                        DataTypes.BlockExecutionType.ENTER, _strategyBlocksParameters[i], oracleState
                    );

                    info.blocksInfoEnter[i] = StrategyBlockExecutionInfo({
                        oracleStatus: oracleState,
                        blockAddr: _strategyBlocks[i],
                        dynParamsNeeded: dynParamsNeeded,
                        dynParamsType: dynParamsType,
                        dynParamsInfo: dynParamsInfo
                    });
                }
            }
        }
    }

    /**
     * @dev Return strategy exit execution information for a specific vault
     * @param _vault vault address
     */
    function getVaultStrategyExitExecutionInfo(address _vault)
        external
        view
        returns (StrategVaultExecutionInfo memory info)
    {
        DataTypes.VaultConfigurationMap memory config = IStrategVault(_vault).configuration();
        IStrategVault vault = IStrategVault(_vault);

        (address[] memory _strategyBlocks, bytes[] memory _strategyBlocksParameters,,) = vault.getStrat();
        uint256 strategyBlocksLength = config.getStrategyBlocksLength();

        if (strategyBlocksLength == 0) return info;

        DataTypes.OracleState memory _tmp;
        _tmp.vault = address(_vault);

        info.startOracleStatus = _tmp;
        info.blocksLength = strategyBlocksLength;
        info.blocksInfo = new StrategyBlockExecutionInfo[](
            strategyBlocksLength
        );

        if (strategyBlocksLength == 1) {
            (bool dynParamsNeeded, DataTypes.DynamicParamsType dynParamsType, bytes memory dynParamsInfo) =
            IStrategStrategyBlock(_strategyBlocks[0]).dynamicParamsInfo(
                DataTypes.BlockExecutionType.EXIT, _strategyBlocksParameters[0], _tmp
            );

            _tmp = IStrategStrategyBlock(_strategyBlocks[0]).oracleExit(_tmp, _strategyBlocksParameters[0]);

            info.blocksInfo[0] = StrategyBlockExecutionInfo({
                oracleStatus: _tmp,
                blockAddr: _strategyBlocks[0],
                dynParamsNeeded: dynParamsNeeded,
                dynParamsType: dynParamsType,
                dynParamsInfo: dynParamsInfo
            });
        } else {
            uint256 revertedIndex = strategyBlocksLength - 1;
            for (uint256 i = 0; i < strategyBlocksLength; i++) {
                uint256 index = revertedIndex - i;

                (bool dynParamsNeeded, DataTypes.DynamicParamsType dynParamsType, bytes memory dynParamsInfo) =
                IStrategStrategyBlock(_strategyBlocks[index]).dynamicParamsInfo(
                    DataTypes.BlockExecutionType.EXIT, _strategyBlocksParameters[index], _tmp
                );

                _tmp = IStrategStrategyBlock(_strategyBlocks[index]).oracleExit(_tmp, _strategyBlocksParameters[index]);

                info.blocksInfo[index] = StrategyBlockExecutionInfo({
                    oracleStatus: _tmp,
                    blockAddr: _strategyBlocks[index],
                    dynParamsNeeded: dynParamsNeeded,
                    dynParamsType: dynParamsType,
                    dynParamsInfo: dynParamsInfo
                });
            }
        }
    }

    /**
     * @dev Return strategy harvest execution information for a specific vault
     * @param _vault vault address
     */
    function getVaultHarvestExecutionInfo(address _vault)
        public
        returns (StrategVaultHarvestExecutionInfo memory info)
    {
        IStrategVault vault = IStrategVault(_vault);
        DataTypes.VaultConfigurationMap memory config = vault.configuration();

        (,, address[] memory _harvestBlocks, bytes[] memory _harvestBlocksParameters) = vault.getStrat();
        uint256 harvestBlocksLength = config.getHarvestBlocksLength();

        if (harvestBlocksLength == 0) return info; 

        DataTypes.OracleState memory _tmp;
        _tmp.vault = address(this);

        info.startOracleStatus = _tmp;
        info.blocksLength = harvestBlocksLength;
        info.blocksInfo = new StrategyBlockExecutionInfo[](harvestBlocksLength);
        for (uint256 i = 0; i < harvestBlocksLength; i++) {
            (bool dynParamsNeeded, DataTypes.DynamicParamsType dynParamsType, bytes memory dynParamsInfo) =
            IStrategHarvestBlock(_harvestBlocks[i]).dynamicParamsInfo(
                DataTypes.BlockExecutionType.HARVEST, _harvestBlocksParameters[i], _tmp
            );

            _tmp = IStrategHarvestBlock(_harvestBlocks[i]).oracleHarvest(_tmp, _harvestBlocksParameters[i]);

            info.blocksInfo[i] = StrategyBlockExecutionInfo({
                oracleStatus: _tmp,
                blockAddr: _harvestBlocks[i],
                dynParamsNeeded: dynParamsNeeded,
                dynParamsType: dynParamsType,
                dynParamsInfo: dynParamsInfo
            });
        }

        uint256 totalSupply = vault.totalSupply();
        uint256 currentVaultIndex = (vault.totalAssets() * 10000) / totalSupply;
        uint256 lastFeeHarvestIndexDiff = currentVaultIndex - config.getLastHarvestIndex();
        uint256 taxableValue = (lastFeeHarvestIndexDiff * totalSupply) / 10000;

        info.receivedAmount = (taxableValue * config.getHarvestFee()) / 10000;
    }

    /**
     * @dev Return vault's strategy configuration and informations
     * @param _vault vault address
     */
    function vaultInfo(address _vault) external returns (StrategVaultInfo memory status) {
        DataTypes.VaultConfigurationMap memory config = IStrategVault(_vault).configuration();
        status.owner = IStrategVault(_vault).owner();
        status.asset = IStrategVault(_vault).asset();
        status.gasAvailable = _getAvailableGas(_vault);
        status.totalSupply = IStrategVault(_vault).totalSupply();
        status.totalAssets = IStrategVault(_vault).totalAssets();
        status.bufferAssetsAvailable = IERC20(status.asset).allowance(IStrategVault(_vault).buffer(), _vault);
        status.bufferSize = config.getBufferSize();
        status.bufferDerivation = config.getBufferDerivation();
        status.harvestFee = config.getHarvestFee();
        status.creatorFee = config.getCreatorFee();
        status.lastHarvestIndex = config.getLastHarvestIndex();
        status.minSupplyForActivation = IStrategVault(_vault).vaultMinDeposit();
        status.currentVaultIndex = status.totalSupply == 0 ? 10000 : (status.totalAssets * 10000) / status.totalSupply;
        status.middleware = config.getMiddlewareStrategy();
        if (config.getHarvestBlocksLength() > 0) {
            status.onHarvestNativeAssetReceived = getVaultHarvestExecutionInfo(_vault).blocksInfo[config
                .getHarvestBlocksLength() - 1].oracleStatus.findTokenAmount(status.asset);
        }
    }

    /**
     * @dev Return available sponsorized gas for a specific vault
     * @param _vault vault address
     */
    function _getAvailableGas(address _vault) internal view returns (uint256 availableGas) {
        availableGas = IERC20(address(paymentToken)).balanceOf(_vault);
        (, uint256[] memory amounts) = paymentToken.getSponsors(_vault);
        for (uint256 i = 0; i < amounts.length; i++) {
            availableGas += amounts[i];
        }
    }
}

