// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./SmartVault.sol";

contract SmartVaultActivePool is SmartVault {
  uint public rewardRatio;
  address public preonRecipient;
  address public dysonRecipient;

  /// @notice Initialize contract after setup it as proxy implementation
  /// @dev Use it only once after first logic setup
  /// @param _name ERC20 name
  /// @param _symbol ERC20 symbol
  /// @param _controller Controller address
  /// @param __underlying Vault underlying address
  /// @param _duration Rewards duration
  /// @param _rewardToken Reward token address. Set zero address if not requires
  function initializeSmartVaultActivePool(
    string memory _name,
    string memory _symbol,
    address _controller,
    address __underlying,
    uint256 _duration,
    address _rewardToken,
    uint _depositFee,
    address _preonRecipient,
    address _dysonRecipient
  ) public initializer {
    SmartVault.initializeSmartVault(_name, _symbol, _controller, __underlying, _duration, _rewardToken, _depositFee);
    preonRecipient = _preonRecipient;
    dysonRecipient = _dysonRecipient;
    rewardRatio = 80;
  }

  function _rebase() internal override {
    uint256 _totalSupply = totalSupply();
    uint _pps = getPricePerFullShare();

    if (_totalSupply > 0 && _pps > 1e18) {
      uint256 _rebaseValue = (_totalSupply * _pps / 1e18) - _totalSupply;
      uint rewardAmount1 = (_rebaseValue * rewardRatio) / 100;
      uint rewardAmount2 = _rebaseValue - rewardAmount1;
      _mint(preonRecipient, rewardAmount1);
      _mint(dysonRecipient, rewardAmount2);
    }
  }
}

