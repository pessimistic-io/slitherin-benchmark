// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import {ERC4626} from "./ERC4626.sol";
import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {ShareMath} from "./ShareMath.sol";

import {IAggregateVault} from "./IAggregateVault.sol";
import {AggregateVault} from "./AggregateVault.sol";
import {GlobalACL} from "./Auth.sol";
import {PausableVault} from "./PausableVault.sol";

/// @title AssetVault
/// @author Umami DAO
/// @notice ERC4626 implementation for vault receipt tokens
contract AssetVault is ERC4626, PausableVault, GlobalACL {
    using SafeTransferLib for ERC20;

    /// @dev the aggregate vault for the strategy
    AggregateVault public aggregateVault;

    constructor(
        ERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _aggregateVault) 
        ERC4626(_asset, _name, _symbol) GlobalACL(AggregateVault(payable(_aggregateVault)).AUTH()) {
            aggregateVault = AggregateVault(payable(_aggregateVault));
    }

    // DEPOSIT & WITHDRAW
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Deposit a specified amount of assets and mint corresponding shares to the receiver
     * @param assets The amount of assets to deposit
     * @param receiver The address to receive the minted shares
     * @return shares The amount of shares minted for the deposited assets
     */
    function deposit(uint256 assets, address receiver) public override whitelistDisabled whenDepositNotPaused returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");
        require(tvl() + assets <= previewVaultCap(), "AssetVault: over vault cap");
        // lock in pps before deposit handling
        uint depositPPS = pps();
        // Transfer assets to aggregate vault, transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(aggregateVault), assets);
        assets = aggregateVault.handleDeposit(asset, assets, msg.sender);

        shares = ShareMath.assetToShares(assets, depositPPS, decimals);
        _mint(receiver,  shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    /**
     * @notice Mint a specified amount of shares and deposit the corresponding amount of assets to the receiver
     * @param shares The amount of shares to mint
     * @param receiver The address to receive the deposited assets
     * @return assets The amount of assets deposited for the minted shares
     */
    function mint(uint256 shares, address receiver) public override whitelistDisabled whenDepositNotPaused returns (uint256 assets) {
        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.
        require(tvl() + assets <= previewVaultCap(), "AssetVault: over vault cap");
        // lock in pps before deposit handling
        uint depositPPS = pps();
        // Need to transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(aggregateVault), assets);
        assets = aggregateVault.handleDeposit(asset, assets, receiver);

        shares = ShareMath.assetToShares(assets, depositPPS, decimals);
        _mint(receiver,  shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    /**
     * @notice Withdraw a specified amount of assets by burning corresponding shares from the owner
     * @param assets The amount of assets to withdraw
     * @param receiver The address to receive the withdrawn assets
     * @param owner The address of the share owner
     * @return shares The amount of shares burned for the withdrawn assets
     */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override whenWithdrawalNotPaused returns (uint256 shares) {
        assets += previewWithdrawalFee(assets);
        shares = ShareMath.assetToShares(assets, pps(), decimals);
        require(shares > 0, "AssetVault: !shares > 0");
        if (msg.sender != owner) {
            _checkAllowance(owner, shares);
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        assets = aggregateVault.handleWithdraw(asset, assets, receiver);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /**
     * @notice Redeem a specified amount of shares by burning them and transferring the corresponding amount of assets to the receiver
     * @param shares The amount of shares to redeem
     * @param receiver The address to receive the corresponding assets
     * @param owner The address of the share owner
     * @return assets The amount of assets transferred for the redeemed shares
     */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override whenWithdrawalNotPaused returns (uint256 assets) {
        require(shares > 0, "AssetVault: !shares > 0");
        assets = totalSupply == 0 ? shares : ShareMath.sharesToAsset(shares, pps(), decimals);
        if (msg.sender != owner) {
            _checkAllowance(owner, shares);
        }
        
        // Check for rounding error since we round down in previewRedeem.
        require(previewRedeem(shares) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        assets = aggregateVault.handleWithdraw(asset, assets, receiver);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    // WHITELIST DEPOSIT
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Deposit a specified amount of assets for whitelisted users and mint corresponding shares to the receiver
     * @param assets The amount of assets to deposit
     * @param receiver The address to receive the minted shares
     * @param merkleProof The merkle proof required for whitelisted deposits
     * @return shares The amount of shares minted for the deposited assets
     */
    function whitelistDeposit(uint256 assets, address receiver, bytes32[] memory merkleProof) public whitelistEnabled whenDepositNotPaused returns (uint256 shares) {
        // Check vault cap
        require(tvl() + assets <= previewVaultCap(), "AssetVault: over vault cap");
        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");
        // checks for whitelist
        aggregateVault.whitelistedDeposit(asset, msg.sender, assets, merkleProof);
        // lock in pps before deposit handling
        uint depositPPS = pps();
        // Transfer assets to aggregate vault, transfer before minting or ERC777s could reenter.
        asset.safeTransferFrom(msg.sender, address(aggregateVault), assets);
        assets = aggregateVault.handleDeposit(asset, assets, msg.sender);

        shares = ShareMath.assetToShares(assets, depositPPS, decimals);
        _mint(receiver,  shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }


    // MATH
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Get the total assets in the vault
     * @return - The total assets in the vault
     */
    function totalAssets() public view override returns (uint256){
        return ShareMath.sharesToAsset(totalSupply, pps(), decimals);
    }

    /**
     * @notice Convert a specified amount of assets to shares
     * @param assets The amount of assets to convert
     * @return - The amount of shares corresponding to the given assets
     */
    function convertToShares(uint256 assets) public view override returns (uint256) {
        return totalSupply == 0 ? assets : ShareMath.assetToShares(assets, pps(), decimals);
    }

    /**
     * @notice Convert a specified amount of shares to assets
     * @param shares The amount of shares to convert
     * @return - The amount of assets corresponding to the given shares
     */
    function convertToAssets(uint256 shares) public view override returns (uint256) {
        return totalSupply == 0 ? shares : ShareMath.sharesToAsset(shares, pps(), decimals);
    }

    /**
     * @notice Preview the amount of shares for a given deposit amount
     * @param assets The amount of assets to deposit
     * @return - The amount of shares for the given deposit amount
     */
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        uint assetFee = previewDepositFee(assets);
        if (assetFee >= assets) return 0;
        return convertToShares(assets - assetFee);
    }

    /**
     * @notice Preview the amount of assets for a given mint amount
     * @param shares The amount of shares to mint
     * @return _mintAmount The amount of assets for the given mint amount
     */
    function previewMint(uint256 shares) public view override returns (uint256 _mintAmount) {
        _mintAmount = totalSupply == 0 ? shares : ShareMath.sharesToAsset(shares, pps(), decimals);
        // add deposit fee for minting fixed amount of shares
        _mintAmount = _mintAmount + previewDepositFee(_mintAmount);
    }

    /**
     * @notice Preview the amount of shares for a given withdrawal amount
     * @param assets The amount of assets to withdraw
     * @return _withdrawAmount The amount of shares for the given withdrawal amount
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256 _withdrawAmount) {
        uint assetFee = previewWithdrawalFee(assets);
        if (assetFee >= assets) return 0;
        _withdrawAmount = totalSupply == 0 ? assets : ShareMath.assetToShares(assets - assetFee, pps(), decimals);
    }

    /**
     * @notice Preview the amount of assets for a given redeem amount
     * @param shares The amount of shares to redeem
     * @return The amount of assets for the given redeem amount
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint assets = ShareMath.sharesToAsset(shares, pps(), decimals);
        uint assetFee = previewWithdrawalFee(assets);
        if (assetFee >= assets) return 0;
        return assets - assetFee;
    }


    // DEPOSIT & WITHDRAW LIMIT
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Get the maximum deposit amount for an address
     * @dev _address The address to check the maximum deposit amount for
     * @dev returns the maximum deposit amount for the given address
     */
    function maxDeposit(address) public view override returns (uint256) {
        uint cap = previewVaultCap();
        uint tvl = tvl();
        return cap > tvl ? cap - tvl : 0; 
    }

    /**
     * @notice Get the maximum mint amount for an address
     */
    function maxMint(address) public view override returns (uint256) {
        uint cap = previewVaultCap();
        uint tvl = tvl();
        return cap > tvl ? convertToShares(cap - tvl) : 0; 
    }

    /**
     * @notice Get the maximum withdrawal amount for an address
     * @param owner The address to check the maximum withdrawal amount for
     * @return The maximum withdrawal amount for the given address
     */
    function maxWithdraw(address owner) public view override returns (uint256) {
        uint aggBalance = asset.balanceOf(address(aggregateVault));
        uint userMaxAssets = convertToAssets(balanceOf[owner]);
        return aggBalance > userMaxAssets ? userMaxAssets : aggBalance;
    }

    /**
     * @notice Get the maximum redeem amount for an address
     * @param owner The address to check the maximum redeem amount for
     * @return - The maximum redeem amount for the given address
     */
    function maxRedeem(address owner) public view override returns (uint256) {
        uint aggBalance = convertToShares(asset.balanceOf(address(aggregateVault)));
        return aggBalance > balanceOf[owner] ? balanceOf[owner] : aggBalance;
    }

    // UTILS
    // ------------------------------------------------------------------------------------------

    /**
     * @notice Pause deposit and withdrawal operations
     */
    function pauseDepositWithdraw() external onlyAggregateVault {
        _pause();
    }

    /**
     * @notice Unpause deposit and withdrawal operations
     */
    function unpauseDepositWithdraw() external onlyAggregateVault {
        _unpause();
    }

    /**
     * @notice Pause deposits operations
     */
    function pauseDeposits() external onlyConfigurator {
        _pauseDeposit();
    }

    /**
     * @notice Unpause deposit operations
     */
    function unpauseDeposits() external onlyConfigurator {
        _unpauseDeposit();
    }

    /**
     * @notice Pause withdrawal operations
     */
    function pauseWithdrawals() external onlyConfigurator {
        _pauseWithdrawal();
    }

    /**
     * @notice Unpause withdrawal operations
     */
    function unpauseWithdrawals() external onlyConfigurator {
        _unpauseWithdrawal();
    }

    /**
     * @notice Get the price per share (PPS) of the vault
     * @return pricePerShare The current price per share
     */
    function pps() public view returns (uint256 pricePerShare) {
        (bool success, bytes memory ret) = address(aggregateVault).staticcall(abi.encodeCall(AggregateVault.getVaultPPS, address(this)));

        // bubble up error message
        if (!success) {
            assembly {
                let length := mload(ret)
                revert(add(32, ret), length)
            }
        }

        pricePerShare = abi.decode(ret, (uint));
    }

    /**
     * @notice Get the total value locked (TVL) of the vault
     * @return totalValueLocked The current total value locked
     */
    function tvl() public view returns (uint256 totalValueLocked) {
        (bool success, bytes memory ret) = address(aggregateVault).staticcall(abi.encodeCall(AggregateVault.getVaultTVL, address(this)));

        // bubble up error message
        if (!success) {
            assembly {
                let length := mload(ret)
                revert(add(32, ret), length)
            }
        }
        totalValueLocked = abi.decode(ret, (uint));
    }

    /**
     * @notice Update the aggregate vault to a new instance
     * @param _newAggregateVault The new aggregate vault instance to update to
     */
    function updateAggregateVault(AggregateVault _newAggregateVault) external onlyConfigurator {
        aggregateVault = _newAggregateVault;
    }

    /**
     * @notice Mint a specified amount of shares to a timelock contract
     * @param _mintAmount The amount of shares to mint
     * @param _timelockContract The address of the timelock contract to receive the minted shares
     */
    function mintTimelockBoost(uint256 _mintAmount, address _timelockContract) external onlyAggregateVault {
        _mint(_timelockContract, _mintAmount);
    }

    /**
     * @notice Preview the deposit fee for a specified amount of assets
     * @param size The amount of assets to preview the deposit fee for
     * @return totalDepositFee The total deposit fee for the specified amount of assets
     */
    function previewDepositFee(uint256 size) public view returns (uint256 totalDepositFee) {
        (bool success, bytes memory ret) = address(aggregateVault).staticcall(abi.encodeCall(AggregateVault.previewDepositFee, (size)));
        if (!success) {
            assembly {
                let length := mload(ret)
                revert(add(32, ret), length)
            }
        }
        totalDepositFee = abi.decode(ret, (uint256));
    }

    /**
     * @notice Preview the withdrawal fee for a specified amount of assets
     * @param size The amount of assets to preview the withdrawal fee for
     * @return totalWithdrawalFee The total withdrawal fee for the specified amount of assets
     */
    function previewWithdrawalFee(uint256 size) public view returns (uint256 totalWithdrawalFee) {
        (bool success, bytes memory ret) = address(aggregateVault).staticcall(abi.encodeCall(AggregateVault.previewWithdrawalFee, (address(asset), size)));
        if (!success) {
            assembly {
                let length := mload(ret)
                revert(add(32, ret), length)
            }
        }
        totalWithdrawalFee = abi.decode(ret, (uint256));
    }

    /**
     * @notice Preview the deposit cap for the vault
     * @return - The current deposit cap for the vault
     */
     function previewVaultCap() public view returns (uint256) {
        return aggregateVault.previewVaultCap(address(asset));
    }

    /**
     * @dev Check the owners spend allowance
     */
     function _checkAllowance(address owner, uint256 shares) internal {
        uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.
        if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
    }
    

    // MODIFIERS
    // ------------------------------------------------------------------------------------------


    /**
     * @dev Modifier that throws if called by any account other than the admin (AggregateVault)
     */
    modifier onlyAggregateVault() {
        require(msg.sender == address(aggregateVault), "AssetVault: Caller is not AggregateVault");
        _;
    }

    /**
     * @dev Modifier that throws if whitelist is not enabled
     */
    modifier whitelistEnabled() {
        require(aggregateVault.whitelistEnabled());
        _;
    }

    /**
     * @dev Modifier that throws if whitelist is enabled
     */
    modifier whitelistDisabled() {
        require(!aggregateVault.whitelistEnabled());
        _;
    }

}

