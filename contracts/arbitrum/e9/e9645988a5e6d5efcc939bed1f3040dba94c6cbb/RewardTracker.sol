// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./BaseToken.sol";
import { IBaseDistributor, IRewardTracker } from "./Interfaces.sol";

contract RewardTracker is IRewardTracker, BaseToken, ReentrancyGuard {
  using SafeERC20 for IERC20;
  uint public constant PRECISION = 1e30;
  uint public constant BASIS_POINTS_DIVISOR = 1e4;

  address public distributor;
  mapping(address => bool) public isDepositToken;
  mapping(address => mapping(address => uint)) public depositBalances; // account => depositToken => amount

  bool public inPrivateStakingMode;
  bool public inPrivateClaimingMode;

  // Tracking rewardPerSecond
  uint public cumulativeRewardPerToken;
  mapping(address => uint) public stakedAmounts;
  mapping(address => uint) public claimableReward;
  mapping(address => uint) public previousCumulatedRewardPerToken;

  // Vesting
  mapping(address => uint) public cumulativeRewards;
  mapping(address => uint) public averageStakedAmounts;

  constructor(string memory _name, string memory _symbol) BaseToken(_name, _symbol, true) {
    inPrivateStakingMode = true;
    inPrivateClaimingMode = true;
  }

  function updateRewards() external nonReentrant {
    _updateRewards(address(0));
  }

  function claim(address _receiver) external nonReentrant returns (uint) {
    if (inPrivateClaimingMode) revert UNAUTHORIZED(string.concat(symbol(), ': ', 'action not enabled'));
    return _claim(msg.sender, _receiver);
  }

  function stake(address _depositToken, uint _amount) external nonReentrant {
    if (inPrivateStakingMode) revert UNAUTHORIZED(string.concat(symbol(), ': ', 'action not enabled'));
    _stake(msg.sender, msg.sender, _depositToken, _amount);
  }

  function unstake(address _depositToken, uint _amount) external nonReentrant {
    if (inPrivateStakingMode) revert UNAUTHORIZED(string.concat(symbol(), ': ', 'action not enabled'));
    _unstake(msg.sender, _depositToken, _amount, msg.sender);
  }

  /** HANDLER */

  function stakeForAccount(
    address _fundingAccount,
    address _account,
    address _depositToken,
    uint _amount
  ) external nonReentrant {
    _validateHandler();
    _stake(_fundingAccount, _account, _depositToken, _amount);
  }

  function unstakeForAccount(
    address _account,
    address _depositToken,
    uint _amount,
    address _receiver
  ) external nonReentrant {
    _validateHandler();
    _unstake(_account, _depositToken, _amount, _receiver);
  }

  function claimForAccount(address _account, address _receiver) external nonReentrant returns (uint) {
    _validateHandler();
    return _claim(_account, _receiver);
  }

  /** VIEWS */
  function rewardToken() public view returns (address) {
    return IBaseDistributor(distributor).rewardToken();
  }

  function tokensPerSecond() external view returns (uint128) {
    return IBaseDistributor(distributor).tokensPerSecond();
  }

  function stakedSynthAmounts(address _account) external view returns (uint) {
    unchecked {
      return (stakedAmounts[_account] * IBaseDistributor(distributor).getRate()) / BASIS_POINTS_DIVISOR;
    }
  }

  function claimable(address _account) external view returns (uint) {
    uint _stakedAmounts = stakedAmounts[_account];
    if (_stakedAmounts == 0) {
      return claimableReward[_account];
    }

    unchecked {
      uint _supply = totalSupply();
      uint _pendingRewards = IBaseDistributor(distributor).pendingRewards() * PRECISION;
      uint nextCumulativeRewardPerToken = cumulativeRewardPerToken + (_pendingRewards / _supply);

      return
        claimableReward[_account] +
        (_stakedAmounts * (nextCumulativeRewardPerToken - previousCumulatedRewardPerToken[_account])) /
        PRECISION;
    }
  }

  /** PRIVATE */
  function _stake(address _fundingAccount, address _account, address _depositToken, uint _amount) private {
    if (_amount == 0) revert FAILED(string.concat(symbol(), ': ', 'invalid amount'));
    if (!isDepositToken[_depositToken]) revert FAILED(string.concat(symbol(), ': ', 'invalid deposit token'));

    _updateRewards(_account);

    unchecked {
      stakedAmounts[_account] += _amount;
      depositBalances[_account][_depositToken] += _amount;
    }

    _mint(_account, _amount);
    IERC20(_depositToken).safeTransferFrom(_fundingAccount, address(this), _amount);
  }

  function _unstake(address _account, address _depositToken, uint _amount, address _receiver) private {
    if (_amount == 0) revert FAILED(string.concat(symbol(), ': ', 'invalid amount'));
    if (!isDepositToken[_depositToken]) revert FAILED(string.concat(symbol(), ': ', 'invalid deposit token'));

    _updateRewards(_account);

    uint _stakedAmounts = stakedAmounts[_account];
    if (_amount > _stakedAmounts) revert FAILED(string.concat(symbol(), ': ', 'amount > stakedAmounts'));
    stakedAmounts[_account] -= _amount;

    uint _depositBalance = depositBalances[_account][_depositToken];
    if (_amount > _depositBalance) revert FAILED(string.concat(symbol(), ': ', 'amount > depositBalance'));
    depositBalances[_account][_depositToken] -= _amount;

    _burn(_account, _amount);
    IERC20(_depositToken).safeTransfer(_receiver, _amount);
  }

  function _claim(address _account, address _receiver) private returns (uint) {
    _updateRewards(_account);

    uint _tokenAmount = claimableReward[_account];
    claimableReward[_account] = 0;

    if (_tokenAmount > 0) {
      IERC20(rewardToken()).safeTransfer(_receiver, _tokenAmount);
      emit Claim(_account, _tokenAmount);
    }

    return _tokenAmount;
  }

  function _updateRewards(address _account) private {
    uint _blockReward = IBaseDistributor(distributor).distribute();
    uint _supply = totalSupply();
    uint _cumulativeRewardPerToken = cumulativeRewardPerToken;

    if (_supply > 0 && _blockReward > 0) {
      unchecked {
        _cumulativeRewardPerToken += (_blockReward * PRECISION) / _supply;
      }
      cumulativeRewardPerToken = _cumulativeRewardPerToken;
    }

    if (_cumulativeRewardPerToken == 0) {
      return;
    }

    if (_account != address(0)) {
      uint _stakedAmount = stakedAmounts[_account];

      uint _accountReward = (_stakedAmount * (_cumulativeRewardPerToken - previousCumulatedRewardPerToken[_account])) /
        PRECISION;

      uint _claimableReward = claimableReward[_account] + _accountReward;

      claimableReward[_account] = _claimableReward;
      previousCumulatedRewardPerToken[_account] = _cumulativeRewardPerToken;

      if (_claimableReward > 0 && _stakedAmount > 0) {
        uint nextCumulativeReward = cumulativeRewards[_account] + _accountReward;

        averageStakedAmounts[_account] =
          ((averageStakedAmounts[_account] * cumulativeRewards[_account]) / nextCumulativeReward) +
          ((_stakedAmount * _accountReward) / nextCumulativeReward);

        cumulativeRewards[_account] = nextCumulativeReward;
      }
    }
  }

  /** OWNER */
  function initialize(address _distributor, address[] memory _depositTokens) external onlyOwner {
    if (distributor != address(0)) revert FAILED(string.concat(symbol(), ': ', 'distributor already set'));

    for (uint i; i < _depositTokens.length; i++) {
      address depositToken = _depositTokens[i];
      isDepositToken[depositToken] = true;
    }

    distributor = _distributor;
  }

  function setDepositToken(address _depositToken, bool _isDepositToken) external onlyOwner {
    isDepositToken[_depositToken] = _isDepositToken;
  }

  function setInPrivateStakingMode(bool _inPrivateStakingMode) external onlyOwner {
    inPrivateStakingMode = _inPrivateStakingMode;
  }

  function setInPrivateClaimingMode(bool _inPrivateClaimingMode) external onlyOwner {
    inPrivateClaimingMode = _inPrivateClaimingMode;
  }
}

