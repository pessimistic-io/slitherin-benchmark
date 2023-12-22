// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.18;

import "./Ownable.sol";
import "./Math.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";

import "./PercentageMath.sol";

import "./IToken.sol";
import "./IErrors.sol";
import "./IVaultDelegator.sol";
import "./IVaultDelegatorErrors.sol";

/// @title Base Delegator
/// @author Christopher Enytc <wagmi@munchies.money>
/// @notice You can use this contract for deploying new delegators
/// @dev All function calls are currently implemented
/// @custom:security-contact security@munchies.money
abstract contract BaseDelegator is Ownable, ReentrancyGuard, IVaultDelegator {
  using Math for uint256;
  using PercentageMath for uint256;

  IERC20 private immutable _asset;
  address private immutable _integrationContract;

  address private _linkedVault;

  uint256 private _claimableThreshold;

  uint256 private _slippageConfiguration;

  bool private _linkedVaultLocked;

  /**
   * @dev Set the underlying asset contract. This must be an ERC20 contract.
   */
  constructor(IERC20 asset_, address integrationContractAddress_) {
    if (integrationContractAddress_ == address(0)) {
      revert ZeroAddressCannotBeUsed();
    }

    _asset = asset_;
    _integrationContract = integrationContractAddress_;

    _claimableThreshold = 1;

    _linkedVaultLocked = false;

    _slippageConfiguration = 100;

    emit ClaimableThresholdUpdated(_claimableThreshold);
  }

  /// @notice Checks if sender is the linked vault
  modifier onlyLinkedVault() {
    if (msg.sender != _linkedVault) {
      revert NotLinkedVault();
    }
    _;
  }

  /// @notice Get the underlying asset
  /// @dev Used to get the address of the asset that was configured on deploy
  /// @return Address of the underlying asset
  function asset() public view returns (address) {
    return address(_asset);
  }

  /// @notice Get the underlying contract
  /// @dev Used to get address of the integration contract that was configured on deploy
  /// @return Address of the underlying integration contract
  function underlyingContract() public view returns (address) {
    return _integrationContract;
  }

  /// @notice Get linked vault
  /// @dev Used to get address of the vault that is linked with the delegator
  /// @return Address of the vault contract
  function linkedVault() public view returns (address) {
    return _linkedVault;
  }

  /// @notice Set linked vault
  /// @dev Used to permanently set the vault of this delegator
  /// @param vault Address of the vault to be linked
  function setLinkedVault(address vault) external onlyOwner {
    if (vault == address(0)) {
      revert ZeroAddressCannotBeUsed();
    }

    if (_linkedVaultLocked) {
      revert CannotSetAnotherLinkedVault();
    }

    _linkedVault = vault;
    _linkedVaultLocked = true;

    emit LinkedVaultUpdated(vault);
  }

  /// @notice Get claimable threshold
  /// @dev Used to get the threshold to used for calling claim on accumulated rewards
  /// @return Threshold in notation of the underlying asset
  function claimableThreshold() public view returns (uint256) {
    return _claimableThreshold;
  }

  /// @notice Set claimable threshold
  /// @dev Used to set the threshold of claims in this delegator
  /// @param threshold Quantity of assets to accumulate before claim
  function setClaimableThreshold(uint256 threshold) external onlyOwner {
    _claimableThreshold = threshold;

    emit ClaimableThresholdUpdated(threshold);
  }

  /// @notice Get slippage configuration
  /// @dev Used to get slippage configuration
  /// @return Amount used for percentageMath
  function slippageConfiguration() public view returns (uint256) {
    return _slippageConfiguration;
  }

  /// @notice Set slippage configuration
  /// @dev Used to set the slippage configuration in this delegator
  /// @param amount used for percentageMath
  function setSlippageConfiguration(uint256 amount) external onlyOwner {
    _slippageConfiguration = amount;

    emit SlippageConfigurationUpdated(amount);
  }

  /// @notice Get delegator name
  /// @dev Used to get the name of the integration used in this delegator
  /// @return Name of the integration
  function delegatorName() external pure virtual returns (string memory) {
    return "base";
  }

  /// @notice Get delegator type
  /// @dev Used to get the type of the integration used in this delegator
  /// @return Type of the integration
  function delegatorType() external pure virtual returns (string memory) {
    return "Delegator";
  }

  /// @notice Get the estimated total assets
  /// @dev Used to get the estimated total of assets deposited in the integration contract
  /// @return Estimated total of assets on the integration contract
  function estimatedTotalAssets() public view virtual returns (uint256) {
    return 0;
  }

  /// @notice Get rewards
  /// @dev Used to get total of rewards accumulated in the integration contract
  /// @return Total amount of assets accumulated
  function rewards() public view virtual returns (uint256) {
    return 0;
  }

  /// @notice Get integration fee for deposits
  /// @dev Used to get the fee charged by the integration contract for deposits
  /// @param amount Amount of assets to apply fee
  /// @return Fee amount charged
  function integrationFeeForDeposits(
    uint256 amount
  ) public view virtual returns (uint256) {
    return _mockedIntegrationFee(amount);
  }

  /// @notice Get integration fee for withdraws
  /// @dev Used to get the fee charged by the integration contract for withdraws
  /// @param amount Amount of assets to apply fee
  /// @return Fee amount charged
  function integrationFeeForWithdraws(
    uint256 amount
  ) public view virtual returns (uint256) {
    return _mockedIntegrationFee(amount);
  }

  /// @dev Get mocked integration fee
  function _mockedIntegrationFee(
    uint256 amount
  ) internal view returns (uint256) {
    uint256 fee = amount.percentMul(slippageConfiguration());

    uint256 feeInAsset = (amount * fee) /
      10 ** IERC20Metadata(asset()).decimals();

    uint256 multiplier = 10_000;

    return multiplier.mulDiv(feeInAsset, amount);
  }

  /// @notice Deposit to integration contract
  /// @dev Used to deposit funds to the integration contract
  /// @param amount Quantity of assets to deposit
  /// @param user Address of the user who requested the deposit
  /// @return Amount deposited in the integration contract
  function deposit(
    uint256 amount,
    address user
  ) external virtual onlyLinkedVault nonReentrant returns (uint256) {
    claim();

    emit Fee(integrationFeeForDeposits(amount));

    emit RequestedDeposit(amount);

    emit Deposited(amount);

    emit RequestedByAddress(user);

    return amount;
  }

  /// @notice Withdraw from integration contract
  /// @dev Used to withdraw funds from the integration contract
  /// @param amount Quantity of assets to withdraw
  /// @param user Address of the user who requested the withdraw
  /// @return Amount withdrawn from the integration contract
  function withdraw(
    uint256 amount,
    address user
  ) public virtual onlyLinkedVault nonReentrant returns (uint256) {
    claim();

    SafeERC20.safeTransfer(_asset, _linkedVault, amount);

    emit Fee(integrationFeeForWithdraws(amount));

    emit RequestedWithdraw(amount);

    emit Withdrawn(amount);

    emit RequestedByAddress(user);

    return amount;
  }

  /// @notice Claim rewards
  /// @dev Used to claim rewards accumulated on the integration contract if the claimable threshold has been reached
  function claim() public virtual {
    if (rewards() < claimableThreshold()) {
      return;
    }
  }

  /// @notice Recover funds
  /// @dev Used to withdraw all funds on the integration contract and send them back to the vault
  function recoverFunds() external virtual onlyLinkedVault {
    withdraw(estimatedTotalAssets(), linkedVault());
  }
}

