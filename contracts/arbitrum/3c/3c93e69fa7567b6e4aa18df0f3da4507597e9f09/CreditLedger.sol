// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./AccessControl.sol";

abstract contract CreditLedger is AccessControl {
  using SafeERC20 for IERC20;

  uint256 private constant creditsConversion = 1E16;

  // Stable coin used
  IERC20 public immutable acceptedToken;

  uint256 private accumulatedRevenue;
  address private treasuryReceiver;

  mapping(address => uint256) private creditBalances;

  constructor(
    IERC20 _acceptedToken,
    address _admin,
    address _treasuryReceiver
  ) AccessControl(_admin) {
    acceptedToken = _acceptedToken;
    treasuryReceiver = _treasuryReceiver;
  }

  function _addRevenue(uint256 _credits) internal {
    accumulatedRevenue = accumulatedRevenue + _credits;
  }

  /**
   * @notice Withdraws all the revenue. Can only be called by admin wallet.
   */
  function withdrawRevenue() external onlyAdmin {
    uint256 withdrawAmount = accumulatedRevenue * creditsConversion;
    accumulatedRevenue = 0;
    acceptedToken.safeTransfer(treasuryReceiver, withdrawAmount);
  }

  function getAccumulatedRevenue() external view returns (uint256) {
    return accumulatedRevenue;
  }

  function getTreasuryReceiver() external view onlyOwner returns (address) {
    return treasuryReceiver;
  }

  function _addCredits(address _user, uint256 _credits) internal {
    creditBalances[_user] = creditBalances[_user] + _credits;
  }

  function _removeCredits(address _user, uint256 _credits) internal {
    require(creditBalances[_user] >= _credits, "Can't have negative credits.");
    creditBalances[_user] = creditBalances[_user] - _credits;
  }

  function creditBalance(address _user) public view returns (uint256) {
    return creditBalances[_user];
  }

  function changeTreasuryReceiver(address _newTreasuryReceiver)
    external
    onlyOwner
  {
    require(_newTreasuryReceiver != address(0), 'address is the zero address');
    treasuryReceiver = _newTreasuryReceiver;
  }

  function convertToCredits(uint256 _stableCoins)
    public
    pure
    returns (uint256)
  {
    return _stableCoins / creditsConversion;
  }

  function convertFromCredits(uint256 _credits) public pure returns (uint256) {
    return _credits * creditsConversion;
  }
}

