// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @title   Automated ERC-4626 Vault Factory.
 * @author  Pulsar Finance
 * @notice  See the following for the full EIP-4626 specification https://eips.ethereum.org/EIPS/eip-4626.
 * @notice  See the following for the full EIP-4626 openzeppelin implementation https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC4626.sol.
 * @dev    VERSION: 1.0
 *          DATE:    2023.08.13
 */

import {Roles} from "./Roles.sol";
import {Enums} from "./Enums.sol";
import {Errors} from "./Errors.sol";
import {Events} from "./Events.sol";
import {ConfigTypes} from "./ConfigTypes.sol";
import {IStrategyWorker} from "./IStrategyWorker.sol";
import {IAutomatedVault} from "./IAutomatedVault.sol";
import {PercentageMath} from "./PercentageMath.sol";
import {IStrategyManager} from "./IStrategyManager.sol";
import {IERC20} from "./ERC20.sol";
import {AccessControl} from "./AccessControl.sol";
import {AbstractAutomatedVaultERC4626} from "./AbstractAutomatedVaultERC4626.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ERC4626} from "./ERC4626.sol";

contract AutomatedVaultERC4626 is
    AbstractAutomatedVaultERC4626,
    IAutomatedVault,
    AccessControl
{
    using SafeERC20 for IERC20;
    using PercentageMath for uint256;

    uint256 public feesAccruedByCreator;
    uint8 public constant MAX_NUMBER_OF_BUY_ASSETS = 5;

    ConfigTypes.StrategyParams private strategyParams;
    ConfigTypes.InitMultiAssetVaultParams private initMultiAssetsVaultParams;

    IStrategyWorker private _strategyWorker;
    IStrategyManager private _strategyManager;

    uint256 public buyAssetsLength;
    address[] public buyAssetAddresses;
    /**
     * @dev Note: Removing entries from dynamic arrays can be gas-expensive.
     * The `getDepositorAddress` array stores all users who have deposited funds in this vault,
     * even if they have already withdrawn their entire balance. Use `balanceOf` to check individual balances.
     */
    address[] public getDepositorAddress;
    uint256 public allDepositorsLength;

    /**
     * @notice Periodic buy amounts are calculated as a percentage of the first deposit and cannot be reset later.
     */
    mapping(address depositor => uint256) private _initialDepositBalances;
    mapping(address depositor => uint256) private _lastUpdatePerDepositor;
    mapping(address depositor => uint256[]) private _depositorBuyAmounts;
    mapping(Enums.BuyFrequency => uint256) private _updateFrequencies;

    constructor(
        ConfigTypes.InitMultiAssetVaultParams memory _initMultiAssetVaultParams,
        ConfigTypes.StrategyParams memory _strategyParams
    )
        AbstractAutomatedVaultERC4626(
            _initMultiAssetVaultParams.depositAsset,
            _initMultiAssetVaultParams.name,
            _initMultiAssetVaultParams.symbol
        )
    {
        if (msg.sender != _initMultiAssetVaultParams.factory) {
            revert Errors.Forbidden("Not factory");
        }
        _validateInputs(
            _initMultiAssetVaultParams.buyAssets,
            _strategyParams.buyPercentages
        );
        _grantRole(Roles.STRATEGY_WORKER, _strategyParams.strategyWorker);
        initMultiAssetsVaultParams = _initMultiAssetVaultParams;
        _populateBuyAssetsData(_initMultiAssetVaultParams);
        strategyParams = _strategyParams;
        _strategyWorker = IStrategyWorker(_strategyParams.strategyWorker);
        _strategyManager = IStrategyManager(_strategyParams.strategyManager);
        initMultiAssetsVaultParams.isActive = false;
        _fillUpdateFrequenciesMap();
    }

    function setLastUpdatePerDepositor(
        address depositor
    ) external onlyRole(Roles.STRATEGY_WORKER) {
        _lastUpdatePerDepositor[depositor] = block.timestamp;
    }

    function getInitMultiAssetVaultParams()
        external
        view
        returns (ConfigTypes.InitMultiAssetVaultParams memory)
    {
        return initMultiAssetsVaultParams;
    }

    function getBuyAssetAddresses() external view returns (address[] memory) {
        return buyAssetAddresses;
    }

    function getStrategyParams()
        external
        view
        returns (ConfigTypes.StrategyParams memory)
    {
        return strategyParams;
    }

    function getInitialDepositBalance(
        address depositor
    ) external view virtual returns (uint256) {
        return _initialDepositBalances[depositor];
    }

    function getDepositorBuyAmounts(
        address depositor
    ) external view virtual returns (uint256[] memory) {
        return _depositorBuyAmounts[depositor];
    }

    function getDepositorTotalPeriodicBuyAmount(
        address depositor
    ) external view returns (uint256 totalPeriodicBuyAmount) {
        if (_depositorBuyAmounts[depositor].length == 0) {
            return 0;
        }
        uint256 _buyAssetsLength = buyAssetsLength;
        for (uint256 i; i < _buyAssetsLength; ) {
            totalPeriodicBuyAmount += _depositorBuyAmounts[depositor][i];
            unchecked {
                ++i;
            }
        }
    }

    function getUpdateFrequencyTimestamp()
        external
        view
        virtual
        returns (uint256)
    {
        return _updateFrequencies[strategyParams.buyFrequency];
    }

    function lastUpdateOf(
        address depositor
    ) external view virtual returns (uint256) {
        return _lastUpdatePerDepositor[depositor];
    }

    function getBatchDepositorAddresses(
        uint256 limit,
        uint256 startAfter
    ) public view returns (address[] memory) {
        uint256 depositorsLength = getDepositorAddress.length;
        if (startAfter >= depositorsLength) {
            revert Errors.InvalidParameters("Invalid interval");
        }
        uint256 counter; /** @dev This is required to copy from a storage array to a memory array.*/
        uint256 startLimit;
        uint256 outputLen;
        if (startAfter + limit <= depositorsLength) {
            startLimit = startAfter + limit;
            outputLen = limit;
        } else {
            startLimit = depositorsLength;
            outputLen = depositorsLength - startAfter;
        }
        address[] memory allDepositors = new address[](outputLen);
        for (uint256 i = startAfter; i < startLimit; ) {
            allDepositors[counter] = getDepositorAddress[i];
            unchecked {
                ++i;
                ++counter;
            }
        }
        return allDepositors;
    }

    function _beforeUnderlyingTransferHook(
        address receiver,
        uint256 assets
    ) internal view override {
        ConfigTypes.WhitelistedDepositAsset
            memory whitelistedDepositAsset = _strategyManager
                .getWhitelistedDepositAsset(asset());
        uint256 depositorTotalPeriodicBuyAmount;
        if (_depositorBuyAmounts[receiver].length == 0) {
            uint256 _buyAssetsLength = buyAssetsLength;
            for (uint256 i; i < _buyAssetsLength; ) {
                depositorTotalPeriodicBuyAmount += assets.percentMul(
                    strategyParams.buyPercentages[i]
                );
                unchecked {
                    ++i;
                }
            }
        } else {
            depositorTotalPeriodicBuyAmount = this
                .getDepositorTotalPeriodicBuyAmount(receiver);
        }
        if (depositorTotalPeriodicBuyAmount == 0) {
            revert Errors.InvalidParameters(
                "Deposit amount lower that the minimum allowed"
            );
        }
        uint256 maxNumberOfStrategyActions = _calculateStrategyMaxNumberOfActionsBalanceBased(
                depositorTotalPeriodicBuyAmount,
                maxWithdraw(receiver),
                assets
            );
        /** @dev maxNumberOfStrategyActions vs max allowed value is checked inside simulateMinDepositValue */
        uint256 minDepositValue = _strategyManager.simulateMinDepositValue(
            whitelistedDepositAsset,
            maxNumberOfStrategyActions,
            strategyParams.buyFrequency,
            initMultiAssetsVaultParams.treasuryPercentageFeeOnBalanceUpdate,
            uint256(getUnderlyingDecimals()),
            maxWithdraw(receiver),
            tx.gasprice
        );
        if (assets < minDepositValue) {
            revert Errors.InvalidParameters(
                "Deposit amount lower that the minimum allowed"
            );
        }
    }

    function _afterUnderlyingTransferHook(
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        address creator = initMultiAssetsVaultParams.creator;
        if (receiver == creator) {
            if (_depositorBuyAmounts[receiver].length == 0 && shares > 0) {
                getDepositorAddress.push(receiver);
                ++allDepositorsLength;
                _initialDepositBalances[receiver] = assets;
                _updateDepositorBuyAmounts(receiver);
            }
            _mint(receiver, shares);
        } else {
            /** @notice if deposit is not from vault creator, a fee will be removed
            from depositor and added to creator balance */
            uint256 creatorPercentage = initMultiAssetsVaultParams
                .creatorPercentageFeeOnDeposit;
            uint256 depositorPercentage = PercentageMath.PERCENTAGE_FACTOR -
                creatorPercentage;
            uint256 creatorShares = shares.percentMul(creatorPercentage);
            uint256 depositorShares = shares.percentMul(depositorPercentage);
            uint256 creatorAssets = assets.percentMul(creatorPercentage);
            uint256 depositorAssets = assets.percentMul(depositorPercentage);

            emit Events.CreatorFeeTransfered(
                address(this),
                creator,
                receiver,
                creatorShares
            );

            if (
                _depositorBuyAmounts[receiver].length == 0 &&
                depositorShares > 0
            ) {
                getDepositorAddress.push(receiver);
                ++allDepositorsLength;
                _initialDepositBalances[receiver] = depositorAssets;
                _updateDepositorBuyAmounts(receiver);
            }
            _mint(receiver, depositorShares);
            _mint(creator, creatorShares);
            feesAccruedByCreator += creatorAssets;
        }
        /** @notice Activates vault after 1st deposit */
        if (!initMultiAssetsVaultParams.isActive && shares > 0) {
            initMultiAssetsVaultParams.isActive = true;
        }
    }

    function _fillUpdateFrequenciesMap() private {
        _updateFrequencies[Enums.BuyFrequency.DAILY] = 86400;
        _updateFrequencies[Enums.BuyFrequency.WEEKLY] = 604800;
        _updateFrequencies[Enums.BuyFrequency.BI_WEEKLY] = 1209600;
        _updateFrequencies[Enums.BuyFrequency.MONTHLY] = 2630016;
    }

    function _validateInputs(
        IERC20[] memory buyAssets,
        uint256[] memory buyPercentages
    ) private pure {
        /** @notice Check if max number of deposited assets was not exceeded */
        if (buyAssets.length > uint256(MAX_NUMBER_OF_BUY_ASSETS)) {
            revert Errors.InvalidParameters(
                "MAX_NUMBER_OF_BUY_ASSETS exceeded"
            );
        }
        /** @notice Check if both arrays have the same length */
        if (buyPercentages.length != buyAssets.length) {
            revert Errors.InvalidParameters(
                "buyPercentages and buyAssets arrays must have the same length"
            );
        }
    }

    function _populateBuyAssetsData(
        ConfigTypes.InitMultiAssetVaultParams memory _initMultiAssetVaultParams
    ) private {
        buyAssetsLength = _initMultiAssetVaultParams.buyAssets.length;
        uint256 _buyAssetsLength = buyAssetsLength;
        for (uint256 i; i < _buyAssetsLength; ) {
            buyAssetAddresses.push(
                address(_initMultiAssetVaultParams.buyAssets[i])
            );
            unchecked {
                ++i;
            }
        }
    }

    function _updateDepositorBuyAmounts(address depositor) internal {
        uint256 initialDepositBalance = _initialDepositBalances[depositor];
        uint256 _buyAssetsLength = buyAssetsLength;
        for (uint256 i; i < _buyAssetsLength; ) {
            _depositorBuyAmounts[depositor].push(
                initialDepositBalance.percentMul(
                    strategyParams.buyPercentages[i]
                )
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev division by zero needs to be previously checked
     */
    function _calculateStrategyMaxNumberOfActionsBalanceBased(
        uint256 depositorTotalPeriodicBuyAmount,
        uint256 depositorCurrentBalance,
        uint256 depositBalance
    ) internal pure returns (uint256 maxNumberOfActions) {
        maxNumberOfActions =
            (depositorCurrentBalance + depositBalance) /
            depositorTotalPeriodicBuyAmount;
    }
}

