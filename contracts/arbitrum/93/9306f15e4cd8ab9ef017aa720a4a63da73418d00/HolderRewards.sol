// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

contract HolderRewards {
  uint256 constant MULTIPLIER = 10 ** 36;

  address public token;
  uint256 public totalStakedUsers;
  uint256 public totalSharesDeposited;

  struct Share {
    uint256 amount;
    uint256 stakedTime;
  }
  struct Reward {
    uint256 totalExcluded;
    uint256 totalRealized;
  }
  mapping(address => Share) shares;
  mapping(address => Reward) public rewards;

  uint256 public totalRewards;
  uint256 public totalDistributed;
  uint256 public rewardsPerShare;

  event AddShares(address indexed user, uint256 amount);
  event RemoveShares(address indexed user, uint256 amount);
  event ClaimReward(address user);
  event DistributeReward(address indexed user, uint256 amount);
  event DepositRewards(address indexed user, uint256 amountTokens);

  modifier onlyToken() {
    require(msg.sender == token, 'ONLYTOKEN');
    _;
  }

  constructor(address _token) {
    token = _token;
  }

  function setShare(
    address shareholder,
    uint256 balanceUpdate,
    bool isRemoving
  ) external onlyToken {
    if (isRemoving) {
      _removeShares(shareholder, balanceUpdate);
      emit RemoveShares(shareholder, balanceUpdate);
    } else {
      _addShares(shareholder, balanceUpdate);
      emit AddShares(shareholder, balanceUpdate);
    }
  }

  function _addShares(address shareholder, uint256 amount) internal {
    if (shares[shareholder].amount > 0) {
      _distributeReward(shareholder);
    }

    uint256 sharesBefore = shares[shareholder].amount;

    totalSharesDeposited += amount;
    shares[shareholder].amount += amount;
    shares[shareholder].stakedTime = block.timestamp;
    if (sharesBefore == 0 && shares[shareholder].amount > 0) {
      totalStakedUsers++;
    }
    rewards[shareholder].totalExcluded = _getCumulativeRewards(
      shares[shareholder].amount
    );
  }

  function _removeShares(address shareholder, uint256 amount) internal {
    require(
      shares[shareholder].amount > 0 && amount <= shares[shareholder].amount,
      'REMOVE: no shares'
    );
    _distributeReward(shareholder);

    totalSharesDeposited -= amount;
    shares[shareholder].amount -= amount;
    if (shares[shareholder].amount == 0) {
      totalStakedUsers--;
    }
    rewards[shareholder].totalExcluded = _getCumulativeRewards(
      shares[shareholder].amount
    );
  }

  function depositRewards() external payable {
    uint256 _amount = msg.value;
    require(_amount > 0, 'DEPOSIT: no ETH');
    require(totalSharesDeposited > 0, 'DEPOSIT: no shares');

    totalRewards += _amount;
    rewardsPerShare += (MULTIPLIER * _amount) / totalSharesDeposited;
    emit DepositRewards(msg.sender, _amount);
  }

  function _distributeReward(address shareholder) internal {
    if (shares[shareholder].amount == 0) {
      return;
    }

    uint256 amount = getUnpaid(shareholder);
    rewards[shareholder].totalRealized += amount;
    rewards[shareholder].totalExcluded = _getCumulativeRewards(
      shares[shareholder].amount
    );

    if (amount > 0) {
      totalDistributed += amount;
      uint256 _balBefore = address(this).balance;
      (bool success, ) = payable(shareholder).call{ value: amount }('');
      require(success, 'DIST: could not distribute');
      require(address(this).balance >= _balBefore - amount, 'DIST: too much');
      emit DistributeReward(shareholder, amount);
    }
  }

  function claimReward() external {
    _distributeReward(msg.sender);
    emit ClaimReward(msg.sender);
  }

  function getUnpaid(address shareholder) public view returns (uint256) {
    if (shares[shareholder].amount == 0) {
      return 0;
    }

    uint256 earnedRewards = _getCumulativeRewards(shares[shareholder].amount);
    uint256 rewardsExcluded = rewards[shareholder].totalExcluded;
    if (earnedRewards <= rewardsExcluded) {
      return 0;
    }

    return earnedRewards - rewardsExcluded;
  }

  function getShares(address user) external view returns (uint256) {
    return shares[user].amount;
  }

  function _getCumulativeRewards(
    uint256 share
  ) internal view returns (uint256) {
    return (share * rewardsPerShare) / MULTIPLIER;
  }
}

