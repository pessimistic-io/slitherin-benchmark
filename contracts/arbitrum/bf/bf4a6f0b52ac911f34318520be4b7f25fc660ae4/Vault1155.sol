// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.10;

import {VaultBase} from "./VaultBase.sol";
import {IAddressesRegistry} from "./IAddressesRegistry.sol";
import {IConnectorRouter} from "./IConnectorRouter.sol";
import {IVault1155} from "./IVault1155.sol";
import {Vault1155logic} from "./Vault1155logic.sol";
import {VaultDataTypes} from "./VaultDataTypes.sol";
import {ISVS} from "./ISVS.sol";
import {VaultErrors} from "./VaultErrors.sol";
import "./IERC20.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./console.sol";

/**
 * @title Vault1155.sol
 * @author Souq.Finance
 * @notice The main ETF contract, responsible for minting and redeeming ETF tokens and rebalancing the ETF
 * @notice License: https://souq-etf.s3.amazonaws.com/LICENSE.md
 */

contract Vault1155 is Initializable, VaultBase, ReentrancyGuardUpgradeable, PausableUpgradeable {
    address internal factory;
    address internal reweighter;
    address internal feeReceiver;
    uint256 public tranchePeriod;
    uint256 public lastTrancheTime;
    uint256[50] private __gap;

    event VITCompositionChanged(address[] VITs, uint256[] newWeights);
    event PoolPaused(address admin);
    event PoolUnpaused(address admin);

    constructor(address _registry) VaultBase(_registry) {}

    function initialize(address _factory, address _feeReceiver) external initializer {
        require(_factory != address(0), VaultErrors.ADDRESS_IS_ZERO);
        require(_feeReceiver != address(0), VaultErrors.ADDRESS_IS_ZERO);
        feeReceiver = _feeReceiver;
        factory = _factory;
        tranchePeriod = 1 days;
        lastTrancheTime = block.timestamp;
        __Pausable_init();
        
    }

    /**
     * @dev Pauses the contract, preventing certain functions from executing.
     */

    function pause() external onlyVaultAdmin {
        _pause();
        emit PoolPaused(msg.sender);
    }

    /**
     * @dev Unpauses the contract, allowing functions to execute.
     */

    function unpause() external onlyVaultAdmin {
        _unpause();
        emit PoolUnpaused(msg.sender);
    }

    /**
     * @dev Calculates the total quote for a specified number of shares and a fee.
     * @param _numShares The number of shares.
     * @param fee The fee amount.
     * @return An array of total quotes.
     */

    function getTotalQuote(uint256 _numShares, uint256 fee) external returns (uint256[] memory) {
        return
            Vault1155logic.getTotalQuote(
                IConnectorRouter(IAddressesRegistry(addressesRegistry).getConnectorsRouter()),
                vaultData.stable,
                vaultData.VITs,
                vaultData.VITAmounts,
                _numShares,
                fee
            );
    }

    /**
     * @dev Calculates the total quote with a specified VIT address and number of shares.
     * @param _VITAddress The VIT address.
     * @param _numShares The number of shares.
     * @return An array of total quotes.
     */

    function getTotalQuoteWithVIT(address _VITAddress, uint256 _numShares) external returns (uint256[] memory) {
        return
            Vault1155logic.getTotalQuoteWithVIT(
                IConnectorRouter(IAddressesRegistry(addressesRegistry).getConnectorsRouter()),
                vaultData.stable,
                vaultData.VITs,
                vaultData.VITAmounts,
                _VITAddress,
                _numShares
            );
    }

    /**
     * @dev Mints Vault tokens for the specified parameters.
     * @param _numShares The number of shares to mint.
     * @param _stableAmount The amount of stable tokens to use for minting.
     * @param _amountPerSwap An array of swap amounts.
     * @param _lockup The lockup period.
     */

    function mintVaultToken(
        uint256 _numShares,
        uint256 _stableAmount,
        uint256[] calldata _amountPerSwap,
        VaultDataTypes.LockupPeriod _lockup
    ) external nonReentrant whenNotPaused {
        calculateTranche();
        VaultDataTypes.MintParams memory params = VaultDataTypes.MintParams({
            numShares: _numShares,
            stableAmount: _stableAmount,
            amountPerSwap: _amountPerSwap,
            lockup: _lockup,
            stable: vaultData.stable,
            VITs: vaultData.VITs,
            VITAmounts: vaultData.VITAmounts,
            currentTranche: vaultData.currentTranche,
            swapRouter: IAddressesRegistry(addressesRegistry).getConnectorsRouter(),
            svs: vaultData.SVS,
            depositFee: vaultData.fee.depositFee,
            vaultAddress: address(this)
        });

        uint256 stableUsed = Vault1155logic.mintVaultToken(feeReceiver, params);
        vaultData.stableDeposited += stableUsed;
    }

    /**
     * @dev Mints Vault tokens for the specified parameters and a specific VIT address and amount.
     * @param _numShares The number of shares to mint.
     * @param _stableAmount The amount of stable tokens to use for minting.
     * @param _amountPerSwap An array of swap amounts.
     * @param _lockup The lockup period.
     * @param _mintVITAddress The VIT address for minting.
     * @param _mintVITAmount The amount of VIT to mint.
     */

    function mintVaultTokenWithVIT(
        uint256 _numShares,
        uint256 _stableAmount,
        uint256[] calldata _amountPerSwap,
        VaultDataTypes.LockupPeriod _lockup,
        address _mintVITAddress,
        uint256 _mintVITAmount
    ) external nonReentrant whenNotPaused {
        require(_mintVITAddress != address(0), VaultErrors.ADDRESS_IS_ZERO);
        calculateTranche();
        VaultDataTypes.MintParams memory params = VaultDataTypes.MintParams({
            numShares: _numShares,
            stableAmount: _stableAmount,
            amountPerSwap: _amountPerSwap,
            lockup: _lockup,
            stable: vaultData.stable,
            VITs: vaultData.VITs,
            VITAmounts: vaultData.VITAmounts,
            currentTranche: vaultData.currentTranche,
            swapRouter: IAddressesRegistry(addressesRegistry).getConnectorsRouter(),
            svs: vaultData.SVS,
            depositFee: vaultData.fee.depositFee,
            vaultAddress: address(this)
        });

        uint256 stableUsed = Vault1155logic.mintVaultTokenWithVIT(feeReceiver, params, _mintVITAddress, _mintVITAmount);
        vaultData.stableDeposited += stableUsed;
    }

    /**
     * @dev Calculates and updates the current tranche based on the tranche period.
     */

    function calculateTranche() internal {
        uint256 blocktime = block.timestamp;
        uint256 currentMidnight = blocktime - (blocktime % 1 days);
        if (blocktime > lastTrancheTime + tranchePeriod) {
            vaultData.currentTranche += vaultData.lockupTimes.length;
            lastTrancheTime = currentMidnight;
        }
        if (ISVS(vaultData.SVS).tokenTranche(vaultData.currentTranche) == 0) {
            ISVS(vaultData.SVS).setTokenTrancheTimestamps(vaultData.currentTranche, vaultData.lockupTimes.length);
        }
    }

    /**
     * @dev Sets the reweighter address.
     * @param _reweighter The new reweighter address.
     */

    function setReweighter(address _reweighter) external onlyVaultAdmin {
        require(_reweighter != address(0), VaultErrors.ADDRESS_IS_ZERO);
        reweighter = _reweighter;
    }

    /**
     * @dev Changes the composition of VITs and their corresponding weights.
     * @param _newVITs An array of new VIT addresses.
     * @param _newAmounts An array of new VIT amounts.
     */

    function changeVITComposition(address[] memory _newVITs, uint256[] memory _newAmounts) external onlyVaultAdmin {
        require(msg.sender == reweighter, VaultErrors.CALLER_NOT_REWEIGHTER);
        require(_newVITs.length == _newAmounts.length, VaultErrors.ARRAY_NOT_SAME_LENGTH);
        for(uint256 i; i < _newVITs.length; ++i)
        {
          require(_newVITs[i] != address(0), VaultErrors.ADDRESS_IS_ZERO);
          require(_newAmounts[i] > 0, VaultErrors.VALUE_IS_ZERO);
        }
        vaultData.VITs = _newVITs;
        vaultData.VITAmounts = _newAmounts;
        emit VITCompositionChanged(_newVITs, _newAmounts);
    }

    /**
     * @dev Initiates a reweight operation for the specified VITs and amounts.
     * @param _VITs An array of VIT addresses to reweight.
     * @param _amounts An array of corresponding amounts for reweighting.
     */

    function initiateReweight(address[] memory _VITs, uint256[] memory _amounts) external onlyVaultAdmin {
        Vault1155logic.initiateReweight(msg.sender, reweighter, _VITs, _amounts);
    }

    function _redeemUnderlying(uint256 _numShares, uint256 _tranche) internal {
        uint256 lockupEnd = getLockupEnd(_tranche);
        Vault1155logic.redeemUnderlying(
            feeReceiver,
            msg.sender,
            vaultData.SVS,
            _numShares,
            _tranche,
            lockupEnd,
            vaultData.VITs,
            vaultData.VITAmounts,
            vaultData.fee.redemptionFee
        );
    }

    /**
     * @dev Redeems underlying assets for the specified number of shares and tranche.
     * @param _numShares The number of shares to redeem.
     * @param _tranche The tranche to redeem from.
     */

    function redeemUnderlying(uint256 _numShares, uint256 _tranche) external nonReentrant whenNotPaused {
        _redeemUnderlying(_numShares, _tranche);
    }

    /**
     * @dev Redeems underlying assets for multiple share quantities and tranches.
     * @param _numShares An array of share quantities to redeem.
     * @param _tranche An array of tranches to redeem from.
     */

    function redeemUnderlyingGroup(uint256[] memory _numShares, uint256[] memory _tranche) external nonReentrant whenNotPaused {
        require(_numShares.length == _tranche.length, VaultErrors.ARRAY_NOT_SAME_LENGTH);
        for (uint256 i = 0; i < _numShares.length; i++) {
            _redeemUnderlying(_numShares[i], _tranche[i]);
        }
    }

    /**
     * @dev Retrieves the lockup start time for a specified tranche.
     * @param _tranche The tranche for which to retrieve the lockup start time.
     * @return The lockup start time in Unix timestamp.
     */

    function getLockupStart(uint256 _tranche) external view returns (uint256) {
        return ISVS(vaultData.SVS).tokenTranche(_tranche);
    }

    /**
     * @dev Retrieves the lockup end time for a specified tranche.
     * @param _tranche The tranche for which to retrieve the lockup end time.
     * @return The lockup end time in Unix timestamp.
     */

    function getLockupEnd(uint256 _tranche) public view returns (uint256) {
        if (vaultData.currentTranche + vaultData.lockupTimes.length <= _tranche) {
            return 0;
        }
        return ISVS(vaultData.SVS).tokenTranche(_tranche) + vaultData.lockupTimes[_tranche % vaultData.lockupTimes.length];
    }

    /**
     * @dev Retrieves the lockup time of a specified tranche.
     * @param _tranche The tranche for which to retrieve the lockup time.
     */

    function getLockupTime(uint256 _tranche) external view returns (uint256) {
        return vaultData.lockupTimes[_tranche % vaultData.lockupTimes.length];
    }

    /**
     * @dev Retrieves the composition of VITs and their corresponding amounts.
     */

    function getVITComposition() external view returns (address[] memory VITs, uint256[] memory amounts) {
        return (vaultData.VITs, vaultData.VITAmounts);
    }

    /**
     * @dev Retrieves the total underlying assets across all VITs.
     */

    function getTotalUnderlying() external view returns (uint256[] memory totalUnderlying) {
        totalUnderlying = Vault1155logic.getTotalUnderlying(vaultData.VITs);
    }

    /**
     * @dev Retrieves the address of the SVS token contract.
     */

    function getSVS() external view returns (address) {
        return vaultData.SVS;
    }

    /**
     * @dev Retrieves the total underlying assets for a specified tranche.
     * @param tranche The tranche for which to retrieve the total underlying assets.
     */

    function getTotalUnderlyingByTranche(uint256 tranche) external view returns (uint256[] memory) {
        return Vault1155logic.getTotalUnderlyingByTranche(vaultData.VITs, vaultData.VITAmounts, vaultData.SVS, tranche);
    }
}

