// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "./Ownable.sol";
import "./Pausable.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./ERC4626.sol";

import "./PercentageMath.sol";

import "./IVault.sol";
import "./IConfiguration.sol";
import "./IVaultDelegator.sol";

/// @title Base Vault
/// @author Christopher Enytc <wagmi@munchies.money>
/// @notice You can use this contract for deploying new vaults
/// @dev All function calls are currently implemented
/// @custom:security-contact security@munchies.money
abstract contract BaseVault is
  Ownable,
  Pausable,
  ReentrancyGuard,
  ERC4626,
  IVault
{
  using PercentageMath for uint256;

  IVaultDelegator public delegator;

  IConfiguration public immutable configuration;

  bool public depositsDisabled;

  /**
   * @dev Set the underlying asset contract. This must be an ERC20 contract.
   */
  constructor(
    IERC20 asset_,
    string memory name_,
    string memory symbol_,
    address delegator_,
    address configuration_
  ) ERC4626(asset_) ERC20(name_, symbol_) {
    // Pause vault for configuration
    //_pause();

    delegator = IVaultDelegator(delegator_);

    configuration = IConfiguration(configuration_);

    // Approve delegator to spend balance from vault for integration with other protocols
    SafeERC20.safeIncreaseAllowance(asset_, delegator_, type(uint256).max);

    depositsDisabled = false;
  }

  modifier whenDepositsNotDisabled() {
    require(!depositsDisabled, "BaseVault: deposits disabled");
    _;
  }

  /// @notice Get the name of the delegator of the vault
  function getDelegatorName() external view returns (string memory) {
    return IVaultDelegator(delegator).delegatorName();
  }

  /// @notice Get the type of the delegator of the vault
  function getDelegatorType() external view returns (string memory) {
    return IVaultDelegator(delegator).delegatorType();
  }

  /// @notice Check if the user has approved the vault to transferFrom asset token
  /// @param user The address of the user
  function checkApproval(address user) external view returns (bool) {
    uint256 approvedAllowance = IERC20(asset()).allowance(user, address(this));

    if (approvedAllowance == type(uint256).max) {
      return true;
    }

    return false;
  }

  /// @notice Check if the user has approved a given allowance to the vault to transferFrom asset token
  /// @param user The address of the user
  /// @param allowance The allowance to check on asset token
  function checkApproval(
    address user,
    uint256 allowance
  ) external view returns (bool) {
    uint256 approvedAllowance = IERC20(asset()).allowance(user, address(this));

    if (approvedAllowance == allowance) {
      return true;
    }

    return false;
  }

  /// @notice Enable user deposits in the vault
  /// @dev Used to make vaults available again
  function enableDeposits() external onlyOwner {
    depositsDisabled = false;
  }

  /// @notice Disable user deposits in the vault
  /// @dev Used to retire vaults
  function disableDeposits() external onlyOwner {
    depositsDisabled = true;
  }

  /// @notice Get deposit fee for an amount
  /// @param amount The amount to discount fee
  function depositFee(uint256 amount) external view returns (uint256) {
    return amount.percentMul(configuration.depositFee());
  }

  /// @notice Get withdraw fee for an amount
  /// @param amount The amount to discount fee
  function withdrawFee(uint256 amount) external view returns (uint256) {
    return amount.percentMul(configuration.withdrawFee());
  }

  /// @notice Initial liquidity of the vault
  /// @dev Used to provide the initial liquidity of the vault
  /// @param assets Amount of assets to deposit
  /// @param receiver Address of the receiver of shares
  function initialDeposit(
    uint256 assets,
    address receiver
  ) external onlyOwner nonReentrant returns (uint256) {
    require(assets <= type(uint256).max, "ERC4626: deposit more than max");

    uint256 shares = previewDeposit(assets);

    _deposit(_msgSender(), receiver, assets, shares);

    // Interact with delegator
    _depositToDelegator(assets);

    return shares;
  }

  /** @dev See {IERC4626-totalAssets}. */
  function totalAssets()
    public
    view
    virtual
    override(ERC4626, IERC4626)
    returns (uint256)
  {
    // Interact with delegator
    return _totalAssetsFromDelegator();
  }

  /// @dev Get total assets from delegator
  function _totalAssetsFromDelegator() internal view returns (uint256) {
    return delegator.totalAssets();
  }

  /** @dev See {IERC4626-deposit}. */
  function deposit(
    uint256 assets,
    address receiver
  )
    public
    virtual
    override(ERC4626, IERC4626)
    whenNotPaused
    whenDepositsNotDisabled
    nonReentrant
    returns (uint256)
  {
    require(assets <= maxDeposit(receiver), "ERC4626: deposit more than max");

    uint256 fee = assets.percentMul(configuration.depositFee());

    uint256 assetsAfterFee = assets - fee;

    uint256 shares = previewDeposit(assetsAfterFee);

    _deposit(_msgSender(), receiver, assets, shares);

    if (fee > 0) {
      _collectFee(fee);
    }

    // Interact with delegator
    _depositToDelegator(assetsAfterFee);

    return shares;
  }

  /** @dev See {IERC4626-mint}. */
  function mint(
    uint256 shares,
    address receiver
  )
    public
    virtual
    override(ERC4626, IERC4626)
    whenNotPaused
    whenDepositsNotDisabled
    nonReentrant
    returns (uint256)
  {
    require(shares <= maxMint(receiver), "ERC4626: mint more than max");

    uint256 assets = previewMint(shares);

    uint256 fee = assets.percentMul(configuration.depositFee());

    uint256 assetsAfterFee = assets - fee;

    uint256 sharesAfterFee = previewDeposit(assetsAfterFee);

    _deposit(_msgSender(), receiver, assets, sharesAfterFee);

    if (fee > 0) {
      _collectFee(fee);
    }

    // Interact with delegator
    _depositToDelegator(assetsAfterFee);

    return assetsAfterFee;
  }

  /// @dev Deposit to delegator integration
  function _depositToDelegator(uint256 amount) internal {
    delegator.deposit(amount);
  }

  /** @dev See {IERC4626-withdraw}. */
  function withdraw(
    uint256 assets,
    address receiver,
    address owner
  )
    public
    virtual
    override(ERC4626, IERC4626)
    whenNotPaused
    nonReentrant
    returns (uint256)
  {
    require(assets <= maxWithdraw(owner), "ERC4626: withdraw more than max");

    uint256 shares = previewWithdraw(assets);

    // Interact with delegator
    _withdrawFromDelegator(assets);

    uint256 fee = assets.percentMul(configuration.withdrawFee());

    uint256 assetsAfterFee = assets - fee;

    _withdraw(_msgSender(), receiver, owner, assetsAfterFee, shares);

    if (fee > 0) {
      _collectFee(fee);
    }

    return shares;
  }

  /** @dev See {IERC4626-redeem}. */
  function redeem(
    uint256 shares,
    address receiver,
    address owner
  )
    public
    virtual
    override(ERC4626, IERC4626)
    whenNotPaused
    nonReentrant
    returns (uint256)
  {
    require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

    uint256 assets = previewRedeem(shares);

    // Interact with delegator
    _withdrawFromDelegator(assets);

    uint256 fee = assets.percentMul(configuration.withdrawFee());

    uint256 assetsAfterFee = assets - fee;

    _withdraw(_msgSender(), receiver, owner, assetsAfterFee, shares);

    if (fee > 0) {
      _collectFee(fee);
    }

    return assetsAfterFee;
  }

  /// @dev Withdraw from delegator integration
  function _withdrawFromDelegator(uint256 amount) internal {
    delegator.withdraw(amount);
  }

  /// @dev Collect protocol fees
  function _collectFee(uint256 fee) internal {
    SafeERC20.safeTransfer(
      IERC20(asset()),
      configuration.protocolTreasury(),
      fee
    );
  }

  /// @notice Pause critical operations in the vault
  /// @dev Only callable by owner
  function pause() external onlyOwner {
    _pause();
  }

  /// @notice Pause critical operations in the vault
  /// @dev Only callable by owner
  function unpause() external onlyOwner {
    _unpause();
  }

  /// @notice Hook to pause transfers if needed
  /// @param from The address of where the funds are coming
  /// @param to The address of where the funds are going
  /// @param amount The amount of the transfer
  /// @dev Only internally used
  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override whenNotPaused {
    super._beforeTokenTransfer(from, to, amount);
  }
}

