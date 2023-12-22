// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { ERC20 } from "./ERC20.sol";
import { ERC4626 } from "./ERC4626.sol";
import { SafeTransferLib } from "./SafeTransferLib.sol";
import { TimelockBoost } from "./TimelockBoostToken.sol";
import { AssetVault } from "./AssetVault.sol";
import { Whitelist } from "./Whitelist.sol";
import { AggregateVault } from "./AggregateVault.sol";

/**
 * @title TimelockZap
 * @author Umami DAO
 * @notice A contract that enables users to easily deposit and withdraw assets from vaults with timelock boost.
 * @dev The TimelockZap contract simplifies the process of depositing and withdrawing assets from vaults with timelock boost.
 */
contract TimelockZap {
    using SafeTransferLib for ERC20;
    using SafeTransferLib for ERC4626;

    /// @notice A struct containing the configuration for a vault with its associated asset and timelock.
    struct VaultConfig {
        address assetVault;
        address timelock;
    }
    /// @notice A mapping that stores the configuration for each input token.
    /// @dev input token => VaultConfig

    mapping(address => VaultConfig) public vaultConfig;
    Whitelist public immutable whitelist;
    AggregateVault public immutable aggregateVault;

    constructor(
        address[5] memory _inputs,
        VaultConfig[5] memory _vaultConfigs,
        address _aggregateVault,
        address _whitelist
    ) {
        vaultConfig[_inputs[0]] = _vaultConfigs[0];
        vaultConfig[_inputs[1]] = _vaultConfigs[1];
        vaultConfig[_inputs[2]] = _vaultConfigs[2];
        vaultConfig[_inputs[3]] = _vaultConfigs[3];
        vaultConfig[_inputs[4]] = _vaultConfigs[4];
        whitelist = Whitelist(_whitelist);
        aggregateVault = AggregateVault(payable(_aggregateVault));
    }

    /**
     * @notice Deposits assets into the associated vault and timelock.
     * @param assets The amount of assets to be deposited.
     * @param receiver The address that will receive the shares.
     * @param asset The address of the asset to be deposited.
     */
    function zapIn(uint256 assets, address receiver, address asset)
        external
        whenWhitelistDisabled
        returns (uint256 _vaultShares, uint256 _timelockedShares)
    {
        VaultConfig memory config = vaultConfig[asset];
        require(config.assetVault != address(0), "TimelockZap: invalid asset");
        require(address(ERC4626(config.assetVault).asset()) == asset, "TimelockZap: invalid asset");
        ERC20(asset).safeTransferFrom(msg.sender, address(this), assets);
        ERC20(asset).safeApprove(config.assetVault, assets);
        _vaultShares = ERC4626(config.assetVault).deposit(assets, address(this));
        ERC4626(config.assetVault).safeApprove(config.timelock, _vaultShares);
        _timelockedShares = ERC4626(config.timelock).deposit(_vaultShares, receiver);
    }

    /**
     * @notice Deposits assets into the associated vault and timelock.
     * @param assets The amount of assets to be deposited.
     * @param receiver The address that will receive the shares.
     * @param asset The address of the asset to be deposited.
     */
    function whitelistZapIn(uint256 assets, address receiver, address asset, bytes32[] calldata proof)
        external
        whenWhitelistEnabled
        returns (uint256 _vaultShares, uint256 _timelockedShares)
    {
        VaultConfig memory config = vaultConfig[asset];
        require(config.assetVault != address(0), "TimelockZap: invalid asset");
        require(address(ERC4626(config.assetVault).asset()) == asset, "TimelockZap: invalid asset");
        ERC20(asset).safeTransferFrom(msg.sender, address(this), assets);

        // account for the deposit limit and whitelist
        if (whitelist.isWhitelistedPriority(asset, msg.sender)) {
            whitelist.whitelistDeposit(asset, msg.sender, assets);
        } else {
            whitelist.whitelistDepositMerkle(asset, msg.sender, assets, proof);
        }

        ERC20(asset).safeApprove(config.assetVault, assets);
        bytes32[] memory emptyProof = new bytes32[](0);
        _vaultShares = AssetVault(config.assetVault).whitelistDeposit(assets, address(this), emptyProof);
        ERC4626(config.assetVault).safeApprove(config.timelock, _vaultShares);
        _timelockedShares = ERC4626(config.timelock).deposit(_vaultShares, receiver);
    }

    /**
     * @notice Withdraws assets from the associated vault and timelock.
     * @param receiver The address that will receive the withdrawn assets.
     * @param asset The address of the asset to be withdrawn.
     */
    function zapOut(address receiver, address asset) external {
        VaultConfig memory config = vaultConfig[asset];
        require(config.assetVault != address(0), "TimelockZap: invalid asset");
        uint256 shares = TimelockBoost(config.timelock).claimWithdrawalsFor(msg.sender, address(this));
        ERC4626(config.assetVault).redeem(shares, receiver, address(this));
    }

    modifier whenWhitelistEnabled() {
        require(aggregateVault.whitelistEnabled(), "TimelockZap: whitelist not enabled");
        _;
    }

    modifier whenWhitelistDisabled() {
        require(!aggregateVault.whitelistEnabled(), "TimelockZap: whitelist not disabled");
        _;
    }
}

