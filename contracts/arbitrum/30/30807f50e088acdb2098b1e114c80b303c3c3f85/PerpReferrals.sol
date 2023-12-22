/******************************************************************************************************
Yieldification Perps Referral Rewards

Website: https://yieldification.com
Twitter: https://twitter.com/yieldification
Telegram: https://t.me/yieldification
******************************************************************************************************/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract PerpReferrals is Ownable {
  using SafeERC20 for IERC20;

  IERC20 public referralToken =
    IERC20(0x30dcBa0405004cF124045793E1933C798Af9E66a);

  uint256 public totalRewards;
  uint256 public totalDistributed;
  mapping(address => uint256) public totalUserRewards;
  mapping(address => uint256) public rewardsClaimed;
  mapping(address => bool) public admins;

  modifier onlyAdmin() {
    require(admins[msg.sender], 'only admins can execute');
    _;
  }

  constructor() {
    admins[owner()] = true;
  }

  function getClaimableRewards(address _user) external view returns (uint256) {
    return totalUserRewards[_user] - rewardsClaimed[_user];
  }

  function claimRewards() external {
    _claimRewards(msg.sender);
  }

  function claimRewardsForUser(address _user) external {
    _claimRewards(_user);
  }

  function _claimRewards(address _user) internal {
    uint256 _claimable = totalUserRewards[_user] - rewardsClaimed[_user];
    require(_claimable > 0, 'must have rewards to claim');
    rewardsClaimed[_user] += _claimable;
    totalDistributed += _claimable;
    referralToken.transfer(_user, _claimable);
  }

  function addRewardsForReferrer(address _referrer, uint256 _newRewards)
    external
    onlyAdmin
  {
    totalUserRewards[_referrer] += _newRewards;
    totalRewards += _newRewards;
  }

  function setAdmin(address _admin, bool _isAdmin) external onlyOwner {
    require(admins[_admin] != _isAdmin, 'must toggle admin');
    admins[_admin] = _isAdmin;
  }

  function setReferralToken(address _token) external onlyOwner {
    referralToken = IERC20(_token);
  }

  function withdrawERC20(address _tokenAddress, uint256 _amount)
    external
    onlyOwner
  {
    IERC20 _contract = IERC20(_tokenAddress);
    _amount = _amount == 0 ? _contract.balanceOf(address(this)) : _amount;
    require(_amount > 0);
    _contract.safeTransfer(owner(), _amount);
  }
}

