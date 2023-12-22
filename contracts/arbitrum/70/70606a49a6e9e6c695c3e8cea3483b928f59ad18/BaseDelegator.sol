// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

import "./IToken.sol";
import "./IVaultDelegator.sol";

abstract contract BaseDelegator is Ownable, IVaultDelegator {
  IERC20 private immutable _asset;
  address private immutable _integrationContract;

  address private _linkedVault;

  uint256 private _claimableThreshold;

  constructor(address asset_, address integrationContract_) {
    _asset = IERC20(asset_);
    _integrationContract = integrationContract_;

    _claimableThreshold = 1;

    emit ClaimableThresholdUpdated(_claimableThreshold);
  }

  function asset() public view returns (address) {
    return address(_asset);
  }

  function underlyingContract() public view returns (address) {
    return _integrationContract;
  }

  function linkedVault() public view returns (address) {
    return _linkedVault;
  }

  function claimableThreshold() public view returns (uint256) {
    return _claimableThreshold;
  }

  function delegatorName() external pure virtual returns (string memory) {
    return "base";
  }

  function delegatorType() external pure virtual returns (string memory) {
    return "Delegator";
  }

  modifier onlyLinkedVault() {
    require(msg.sender == _linkedVault, "BaseDelegator: Not linked vault");
    _;
  }

  function setLinkedVault(address vault) external onlyOwner {
    _linkedVault = vault;

    emit LinkedVaultUpdated(vault);
  }

  function setClaimableThreshold(uint256 threshold) external onlyOwner {
    _claimableThreshold = threshold;

    emit ClaimableThresholdUpdated(threshold);
  }

  function deposit(uint256 amount) external virtual onlyLinkedVault {
    claim();

    SafeERC20.safeTransferFrom(_asset, _linkedVault, address(this), amount);

    emit Deposit(amount);
  }

  function withdraw(uint256 amount) external virtual onlyLinkedVault {
    claim();

    SafeERC20.safeTransfer(_asset, _linkedVault, amount);

    emit Withdraw(amount);
  }

  function totalAssets() public view virtual returns (uint256) {
    return 0;
  }

  function rewards() public view virtual returns (uint256) {
    return 0;
  }

  function claim() public virtual {
    if (rewards() < _claimableThreshold) {
      return;
    }

    emit RewardsClaimed(rewards());
  }
}

