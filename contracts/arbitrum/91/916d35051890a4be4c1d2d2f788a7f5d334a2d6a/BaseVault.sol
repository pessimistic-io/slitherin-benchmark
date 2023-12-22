// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./Ownable.sol";
import "./Math.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./ERC4626.sol";

import "./PercentageMath.sol";

import "./IVault.sol";
import "./IErrors.sol";
import "./IVaultErrors.sol";
import "./IConfiguration.sol";
import "./IVaultDelegator.sol";

/// @title Base Vault
/// @author Christopher Enytc <wagmi@munchies.money>
/// @notice You can use this contract for deploying new vaults
/// @dev All function calls are currently implemented
/// @custom:security-contact security@munchies.money
contract BaseVault is Ownable, ReentrancyGuard, ERC4626, IVault {
  using Math for uint256;
  using PercentageMath for uint256;

  IVaultDelegator public immutable delegator;

  IConfiguration public immutable configuration;

  bool public depositsDisabled;

  bool public emergencyExitEnabled;

  uint256 private _minDepositAllowed;

  uint256 private _maxDepositAllowed;

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
    if (delegator_ == address(0)) {
      revert ZeroAddressCannotBeUsed();
    }

    if (configuration_ == address(0)) {
      revert ZeroAddressCannotBeUsed();
    }

    delegator = IVaultDelegator(delegator_);

    configuration = IConfiguration(configuration_);

    depositsDisabled = true;

    emergencyExitEnabled = false;

    _minDepositAllowed = 0;

    _maxDepositAllowed = type(uint256).max;

    // Allow delegator to use tokens in the contract
    SafeERC20.safeIncreaseAllowance(
      IERC20(asset_),
      delegator_,
      type(uint256).max
    );
  }

  /// @notice Checks if deposits are enabled
  modifier whenDepositsNotDisabled() {
    if (depositsDisabled) {
      revert DepositsDisabled();
    }
    _;
  }

  /// @notice Checks if emergency exit is enabled
  modifier whenEmergencyExitIsEnabled() {
    if (!emergencyExitEnabled) {
      revert EmergencyExitDisabled();
    }
    _;
  }

  /// @notice Checks if emergency exit is disabled
  modifier whenNotOnEmergencyExitMode() {
    if (emergencyExitEnabled) {
      revert EmergencyExitEnabled();
    }
    _;
  }

  /// @notice Get the name of the delegator of the vault
  /// @return Name of the delegator
  function getDelegatorName() external view returns (string memory) {
    return IVaultDelegator(delegator).delegatorName();
  }

  /// @notice Get the type of the delegator of the vault
  /// @return Type of the delegator
  function getDelegatorType() external view returns (string memory) {
    return IVaultDelegator(delegator).delegatorType();
  }

  /// @notice Check if the user has approved the vault to transferFrom asset token
  /// @param user The address of the user
  /// @return Approval status of the user
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
  /// @return Approval status of the user
  function checkApproval(
    address user,
    uint256 allowance
  ) external view returns (bool) {
    uint256 approvedAllowance = IERC20(asset()).allowance(user, address(this));

    if (allowance <= approvedAllowance) {
      return true;
    }

    return false;
  }

  /// @notice Get deposit fee for an amount
  /// @return Fee for deposits in the vault
  function depositFee() public view returns (uint256) {
    return configuration.depositFee();
  }

  /// @notice Get deposit integration fee for an amount
  /// @param amount The amount to discount integration fee
  /// @return Fee for deposits in the integration protocol
  function depositIntegrationFee(uint256 amount) public view returns (uint256) {
    return delegator.integrationFeeForDeposits(amount);
  }

  /// @notice Get total deposit fee for an amount
  /// @param amount The amount to discount fee
  /// @return Fee for deposits in the vault
  function totalFeeForDeposits(uint256 amount) public view returns (uint256) {
    return depositFee() + depositIntegrationFee(amount);
  }

  /// @notice Get an estimation of tokens to be deposited after fees
  /// @param amount The amount to be deposited
  /// @return Amount estimated to be deposited
  function estimateDepositAfterFees(
    uint256 amount
  ) public view returns (uint256) {
    uint256 feeInBps = totalFeeForDeposits(amount);

    return (amount * feeInBps) / 10_000;
  }

  /// @notice Get withdraw fee for an amount
  /// @return Fee for withdraws from the vault
  function withdrawFee() public view returns (uint256) {
    return configuration.withdrawFee();
  }

  /// @notice Get withdraw integration fee for an amount
  /// @param amount The amount to discount integration fee
  /// @return Fee for withdraws in the integration protocol
  function withdrawIntegrationFee(
    uint256 amount
  ) public view returns (uint256) {
    return delegator.integrationFeeForWithdraws(amount);
  }

  /// @notice Get total withdraw fee for an amount
  /// @param amount The amount to discount fee
  /// @return Fee for withdraws in the vault
  function totalFeeForWithdraws(uint256 amount) public view returns (uint256) {
    return withdrawFee() + withdrawIntegrationFee(amount);
  }

  /// @notice Get an estimation of tokens to be withdrawn after fees
  /// @param amount The amount to be withdrawn
  /// @return Amount estimated to be withdrawn
  function estimateWithdrawAfterFees(
    uint256 amount
  ) public view returns (uint256) {
    uint256 feeInBps = totalFeeForWithdraws(amount);

    return (amount * feeInBps) / 10_000;
  }

  /** @dev See {IERC4626-totalAssets}. */
  function totalAssets()
    public
    view
    virtual
    override(ERC4626, IERC4626)
    returns (uint256)
  {
    if (emergencyExitEnabled) {
      return IERC20(asset()).balanceOf(address(this));
    }

    // Interact with delegator
    return _estimatedTotalAssetsFromDelegator();
  }

  /// @dev Get the estimated total assets from delegator
  function _estimatedTotalAssetsFromDelegator()
    internal
    view
    returns (uint256)
  {
    return delegator.estimatedTotalAssets();
  }

  /// @notice Minimum deposit
  /// @dev Used to get the minimum deposit amount of the vault
  /// @return Minimum deposit amount
  function minDeposit() public view returns (uint256) {
    return _minDepositAllowed;
  }

  /// @dev Set new min deposit
  function setMinDeposit(uint256 amount) external onlyOwner {
    _minDepositAllowed = amount;
  }

  /// @notice Maximum deposit
  /// @dev Used to get the maximum deposit amount of the vault
  /// @return Maximum deposit amount
  function maxDeposit() public view returns (uint256) {
    return _maxDepositAllowed;
  }

  /** @dev See {IERC4626-maxDeposit}. */
  function maxDeposit(
    address user
  ) public view virtual override(ERC4626, IERC4626) returns (uint256) {
    uint256 assets = convertToAssets(balanceOf(user));

    if (assets <= _maxDepositAllowed) {
      return _maxDepositAllowed;
    }

    return 0;
  }

  /// @notice Minimum mint
  /// @dev Used to get the minimum mint amount of the vault
  /// @return Minimum mint amount
  function minMint() public view returns (uint256) {
    return convertToShares(_minDepositAllowed);
  }

  /// @notice Maximum mint
  /// @dev Used to get the maximum mint amount of the vault
  /// @return Maximum mint amount
  function maxMint() public view returns (uint256) {
    return convertToShares(_maxDepositAllowed);
  }

  /** @dev See {IERC4626-maxDeposit}. */
  function maxMint(
    address user
  ) public view virtual override(ERC4626, IERC4626) returns (uint256) {
    uint256 assets = convertToAssets(balanceOf(user));

    if (assets <= _maxDepositAllowed) {
      return convertToShares(_maxDepositAllowed);
    }

    return 0;
  }

  /// @dev Set new max deposit
  function setMaxDeposit(uint256 amount) external onlyOwner {
    _maxDepositAllowed = amount;
  }

  /// @notice Initial liquidity of the vault
  /// @dev Used to provide the initial liquidity of the vault
  /// @param assets Amount of assets to deposit
  /// @param receiver Address of the receiver of shares
  /// @return Shares minted in the vault
  function initialDeposit(
    uint256 assets,
    address receiver
  )
    external
    onlyOwner
    whenNotOnEmergencyExitMode
    nonReentrant
    returns (uint256)
  {
    uint256 maxAssets = type(uint256).max;

    if (assets > maxAssets) {
      revert ExceededMaxDeposit(receiver, assets, maxAssets);
    }

    uint256 shares = previewDeposit(assets);

    _deposit(_msgSender(), receiver, assets, shares);

    // Interact with delegator
    // slither-disable-start unused-return
    _depositToDelegator(assets, receiver);
    // slither-disable-end unused-return

    return shares;
  }

  /// @notice Sponsor the vault to boost earnings
  /// @dev Used to boost the earnings of the vault
  /// @param assets Amount of assets to give
  /// @param sponsorName Name of the company or person sponsoring the vault
  /// @return Assets deposited in the delegator
  function sponsorTheVault(
    uint256 assets,
    string memory sponsorName
  )
    external
    onlyOwner
    whenNotOnEmergencyExitMode
    nonReentrant
    returns (uint256)
  {
    address sponsor = _msgSender();

    uint256 balance = IERC20(asset()).balanceOf(sponsor);

    if (assets < balance) {
      revert InsufficientBalance(assets, balance);
    }

    uint256 approvedAllowance = IERC20(asset()).allowance(
      sponsor,
      address(this)
    );

    if (assets < approvedAllowance) {
      revert InsufficientAllowance(assets, approvedAllowance);
    }

    SafeERC20.safeTransferFrom(IERC20(asset()), sponsor, address(this), assets);

    // Interact with delegator
    uint256 assetsDeposited = _depositToDelegator(assets, sponsor);

    emit Sponsored(assetsDeposited, sponsor, sponsorName);

    return assetsDeposited;
  }

  /** @dev See {IERC4626-deposit}. */
  function deposit(
    uint256 assets,
    address receiver
  )
    public
    virtual
    override(ERC4626, IERC4626)
    whenDepositsNotDisabled
    whenNotOnEmergencyExitMode
    nonReentrant
    returns (uint256)
  {
    uint256 minAssets = minDeposit();
    uint256 maxAssets = maxDeposit(receiver);

    if (assets < minAssets) {
      revert BelowMinDeposit(receiver, assets, minAssets);
    }

    if (assets > maxAssets) {
      revert ExceededMaxDeposit(receiver, assets, maxAssets);
    }

    uint256 balance = IERC20(asset()).balanceOf(receiver);

    if (balance < assets) {
      revert InsufficientBalance(assets, balance);
    }

    uint256 approvedAllowance = IERC20(asset()).allowance(
      receiver,
      address(this)
    );

    if (approvedAllowance < assets) {
      revert InsufficientAllowance(assets, approvedAllowance);
    }

    uint256 fee = assets.percentMul(configuration.depositFee());

    uint256 assetsAfterFee = assets - fee;

    uint256 shares = previewDeposit(assetsAfterFee);

    _deposit(_msgSender(), receiver, assets, shares);

    if (fee > 0) {
      _collectFee(fee);
    }

    // Interact with delegator
    // slither-disable-start unused-return
    _depositToDelegator(assetsAfterFee, receiver);
    // slither-disable-end unused-return

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
    whenDepositsNotDisabled
    whenNotOnEmergencyExitMode
    nonReentrant
    returns (uint256)
  {
    uint256 minShares = minMint();
    uint256 maxShares = maxMint(receiver);

    if (shares < minShares) {
      revert BelowMinMint(receiver, shares, minShares);
    }

    if (shares > maxShares) {
      revert ExceededMaxMint(receiver, shares, maxShares);
    }

    uint256 assets = previewMint(shares);

    uint256 balance = IERC20(asset()).balanceOf(receiver);

    if (balance < assets) {
      revert InsufficientBalance(assets, balance);
    }

    uint256 approvedAllowance = IERC20(asset()).allowance(
      receiver,
      address(this)
    );

    if (approvedAllowance < assets) {
      revert InsufficientAllowance(assets, approvedAllowance);
    }

    uint256 fee = assets.percentMul(configuration.depositFee());

    uint256 assetsAfterFee = assets - fee;

    uint256 sharesAfterFee = previewDeposit(assetsAfterFee);

    _deposit(_msgSender(), receiver, assets, sharesAfterFee);

    if (fee > 0) {
      _collectFee(fee);
    }

    // Interact with delegator
    // slither-disable-start unused-return
    _depositToDelegator(assetsAfterFee, receiver);
    // slither-disable-end unused-return

    return assetsAfterFee;
  }

  /// @dev Deposit to delegator integration
  function _depositToDelegator(
    uint256 amount,
    address user
  ) internal returns (uint256) {
    return delegator.deposit(amount, user);
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
    whenNotOnEmergencyExitMode
    nonReentrant
    returns (uint256)
  {
    uint256 maxAssets = maxWithdraw(owner);

    if (assets > maxAssets) {
      revert ExceededMaxWithdraw(owner, assets, maxAssets);
    }

    uint256 shares = previewWithdraw(assets);

    // Interact with delegator
    uint256 receivedAssets = _withdrawFromDelegator(assets, owner);

    uint256 fee = receivedAssets.percentMul(configuration.withdrawFee());

    uint256 assetsAfterFee = receivedAssets - fee;

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
    whenNotOnEmergencyExitMode
    nonReentrant
    returns (uint256)
  {
    uint256 maxShares = maxRedeem(owner);

    if (shares > maxShares) {
      revert ExceededMaxRedeem(owner, shares, maxShares);
    }

    uint256 assets = previewRedeem(shares);

    // Interact with delegator
    uint256 receivedAssets = _withdrawFromDelegator(assets, owner);

    uint256 fee = receivedAssets.percentMul(configuration.withdrawFee());

    uint256 assetsAfterFee = receivedAssets - fee;

    _withdraw(_msgSender(), receiver, owner, assetsAfterFee, shares);

    if (fee > 0) {
      _collectFee(fee);
    }

    return assetsAfterFee;
  }

  /// @dev Withdraw from delegator integration
  function _withdrawFromDelegator(
    uint256 amount,
    address user
  ) internal returns (uint256) {
    return delegator.withdraw(amount, user);
  }

  /// @dev Collect protocol fees
  function _collectFee(uint256 fee) internal {
    SafeERC20.safeTransfer(
      IERC20(asset()),
      configuration.protocolTreasury(),
      fee
    );
  }

  //
  // Emergency exit
  //

  /// @notice Enable emergency exit mode
  /// @dev Used to recover all funds from delegator
  function enableEmergencyExit() external onlyOwner nonReentrant {
    depositsDisabled = true;
    emergencyExitEnabled = true;

    delegator.recoverFunds();
  }

  /// @notice Disable emergency exit mode
  /// @dev Used send funds back to delegator
  function disableEmergencyExit() external onlyOwner nonReentrant {
    depositsDisabled = false;
    emergencyExitEnabled = false;

    uint256 assets = IERC20(asset()).balanceOf(address(this));

    if (assets > 0) {
      _depositToDelegator(assets, address(this));
    }
  }

  /// @notice Emergency exit
  /// @dev Used to let users withdraw without fees in case of emergencies
  /// @param shares Quantity of shares to use to exit the vault
  /// @param receiver Address that will receive the assets
  /// @param owner Address that holds the shares of the vault
  /// @return Assets transfered from the vault
  function emergencyExit(
    uint256 shares,
    address receiver,
    address owner
  ) external whenEmergencyExitIsEnabled nonReentrant returns (uint256) {
    uint256 maxShares = maxRedeem(owner);

    if (shares > maxShares) {
      revert ExceededMaxRedeem(owner, shares, maxShares);
    }

    uint256 assets = previewRedeem(shares);

    _withdraw(_msgSender(), receiver, owner, assets, shares);

    return assets;
  }

  // Admin functions

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
}

