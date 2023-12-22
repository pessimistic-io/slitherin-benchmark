// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8;

import "./IVester.sol";
import "./IMintable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./OwnableUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";

contract Vester is IVester, IERC20, OwnableUpgradeable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;

  bytes32 public constant OPERATOR_ROLE = keccak256('OPERATOR_ROLE');
  bytes32 public constant REWARDER_ROLE = keccak256('REWARDER_ROLE');

  string public name;
  string public symbol;
  uint8 public decimals;

  uint256 public vestingDuration;

  address public esToken;
  address public pairToken;
  address public claimableToken;

  IRewardTracker public override rewardTracker;

  uint256 public override totalSupply;
  uint256 public pairSupply;

  bool public hasMaxVestableAmount;

  mapping(address => uint256) public balances;
  mapping(address => uint256) public override pairAmounts;
  mapping(address => uint256) public override cumulativeClaimAmounts;
  mapping(address => uint256) public override claimedAmounts;
  mapping(address => uint256) public lastVestingTimes;

  mapping(address => uint256) public override transferredAverageStakedAmounts;
  mapping(address => uint256) public override transferredCumulativeRewards;
  mapping(address => uint256) public override cumulativeRewardDeductions;
  mapping(address => uint256) public override bonusRewards;

  function initialize(
    address _owner,
    string calldata _name,
    string calldata _symbol,
    uint256 _vestingDuration,
    address _esToken,
    address _pairToken,
    address _claimableToken,
    IRewardTracker _rewardTracker
  ) external initializer {
    OwnableUpgradeable.__Ownable_init();
    AccessControlUpgradeable.__AccessControl_init();
    ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

    _transferOwnership(_owner);
    _setupRole(DEFAULT_ADMIN_ROLE, _owner);

    name = _name;
    symbol = _symbol;
    decimals = 18;

    vestingDuration = _vestingDuration;

    esToken = _esToken;
    pairToken = _pairToken;
    claimableToken = _claimableToken;

    rewardTracker = _rewardTracker;

    if (address(rewardTracker) != address(0)) {
      hasMaxVestableAmount = true;
    }
  }

  function deposit(uint256 _amount) external nonReentrant {
    _deposit(msg.sender, _amount);
  }

  function depositForAccount(address _account, uint256 _amount) external onlyRole(OPERATOR_ROLE) nonReentrant {
    _deposit(_account, _amount);
  }

  function claim() external nonReentrant returns (uint256) {
    return _claim(msg.sender, msg.sender);
  }

  function claimForAccount(address _account, address _receiver)
    external
    override
    onlyRole(OPERATOR_ROLE)
    nonReentrant
    returns (uint256)
  {
    return _claim(_account, _receiver);
  }

  function withdrawToken(
    address _token,
    address _account,
    uint256 _amount
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    IERC20(_token).safeTransfer(_account, _amount);
  }

  function withdraw() external nonReentrant {
    address account = msg.sender;
    address _receiver = account;
    _claim(account, _receiver);

    uint256 claimedAmount = cumulativeClaimAmounts[account];
    uint256 balance = balances[account];
    uint256 totalVested = balance + claimedAmount;
    require(totalVested > 0, 'Vester: vested amount is zero');

    if (hasPairToken()) {
      uint256 pairAmount = pairAmounts[account];
      _burnPair(account, pairAmount);
      IERC20(pairToken).safeTransfer(_receiver, pairAmount);
    }

    IERC20(esToken).safeTransfer(_receiver, balance);
    _burn(account, balance);

    delete cumulativeClaimAmounts[account];
    delete claimedAmounts[account];
    delete lastVestingTimes[account];

    emit Withdraw(account, claimedAmount, balance);
  }

  function transferStakeValues(address _sender, address _receiver)
    external
    override
    onlyRole(OPERATOR_ROLE)
    nonReentrant
  {
    transferredAverageStakedAmounts[_receiver] = getCombinedAverageStakedAmount(_sender);
    transferredAverageStakedAmounts[_sender] = 0;

    uint256 transferredCumulativeReward = transferredCumulativeRewards[_sender];
    uint256 cumulativeReward = rewardTracker.cumulativeRewards(_sender);

    transferredCumulativeRewards[_receiver] = transferredCumulativeReward + cumulativeReward;
    cumulativeRewardDeductions[_sender] = cumulativeReward;
    transferredCumulativeRewards[_sender] = 0;

    bonusRewards[_receiver] = bonusRewards[_sender];
    bonusRewards[_sender] = 0;
  }

  function setHasMaxVestableAmount(bool _hasMaxVestableAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    hasMaxVestableAmount = _hasMaxVestableAmount;
  }

  function setPairToken(address _pairToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
    pairToken = _pairToken;
  }

  function setRewardTracker(IRewardTracker _rewardTracker) external onlyRole(DEFAULT_ADMIN_ROLE) {
    rewardTracker = _rewardTracker;
  }

  function setTransferredAverageStakedAmounts(address _account, uint256 _amount)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
    nonReentrant
  {
    transferredAverageStakedAmounts[_account] = _amount;
  }

  function setTransferredCumulativeRewards(address _account, uint256 _amount)
    external
    override
    onlyRole(OPERATOR_ROLE)
    nonReentrant
  {
    transferredCumulativeRewards[_account] = _amount;
  }

  function setCumulativeRewardDeductions(address _account, uint256 _amount)
    external
    override
    onlyRole(DEFAULT_ADMIN_ROLE)
    nonReentrant
  {
    cumulativeRewardDeductions[_account] = _amount;
  }

  function setBonusRewards(address _account, uint256 _amount) external override onlyRole(REWARDER_ROLE) nonReentrant {
    bonusRewards[_account] = _amount;
  }

  function claimable(address _account) public view override returns (uint256) {
    uint256 amount = cumulativeClaimAmounts[_account] - claimedAmounts[_account];
    uint256 nextClaimable = _getNextClaimableAmount(_account);
    return amount + nextClaimable;
  }

  function getMaxVestableAmount(address _account) public view override returns (uint256) {
    if (!hasRewardTracker()) {
      return 0;
    }

    uint256 transferredCumulativeReward = transferredCumulativeRewards[_account];
    uint256 bonusReward = bonusRewards[_account];
    uint256 cumulativeReward = rewardTracker.cumulativeRewards(_account);
    uint256 maxVestableAmount = cumulativeReward + transferredCumulativeReward + bonusReward;

    uint256 cumulativeRewardDeduction = cumulativeRewardDeductions[_account];

    if (maxVestableAmount < cumulativeRewardDeduction) {
      return 0;
    }

    return maxVestableAmount - cumulativeRewardDeduction;
  }

  function getCombinedAverageStakedAmount(address _account) public view override returns (uint256) {
    uint256 cumulativeReward = rewardTracker.cumulativeRewards(_account);
    uint256 transferredCumulativeReward = transferredCumulativeRewards[_account];
    uint256 totalCumulativeReward = cumulativeReward + transferredCumulativeReward;
    if (totalCumulativeReward == 0) {
      return 0;
    }

    uint256 averageStakedAmount = rewardTracker.averageStakedAmounts(_account);
    uint256 transferredAverageStakedAmount = transferredAverageStakedAmounts[_account];

    return
      (averageStakedAmount * cumulativeReward) /
      totalCumulativeReward +
      (transferredAverageStakedAmount * transferredCumulativeReward) /
      totalCumulativeReward;
  }

  function getPairAmount(address _account, uint256 _esAmount) public view returns (uint256) {
    if (!hasRewardTracker()) {
      return 0;
    }

    uint256 combinedAverageStakedAmount = getCombinedAverageStakedAmount(_account);
    if (combinedAverageStakedAmount == 0) {
      return 0;
    }

    uint256 maxVestableAmount = getMaxVestableAmount(_account);
    if (maxVestableAmount == 0) {
      return 0;
    }

    return (_esAmount * combinedAverageStakedAmount) / maxVestableAmount;
  }

  function hasRewardTracker() public view returns (bool) {
    return address(rewardTracker) != address(0);
  }

  function hasPairToken() public view returns (bool) {
    return pairToken != address(0);
  }

  function getTotalVested(address _account) public view returns (uint256) {
    return balances[_account] + cumulativeClaimAmounts[_account];
  }

  function balanceOf(address _account) public view override returns (uint256) {
    return balances[_account];
  }

  // empty implementation, tokens are non-transferrable
  function transfer(
    address, /* recipient */
    uint256 /* amount */
  ) public pure override returns (bool) {
    revert('Vester: non-transferrable');
  }

  // empty implementation, tokens are non-transferrable
  function allowance(
    address, /* owner */
    address /* spender */
  ) public view virtual override returns (uint256) {
    return 0;
  }

  // empty implementation, tokens are non-transferrable
  function approve(
    address, /* spender */
    uint256 /* amount */
  ) public virtual override returns (bool) {
    revert('Vester: non-transferrable');
  }

  // empty implementation, tokens are non-transferrable
  function transferFrom(
    address, /* sender */
    address, /* recipient */
    uint256 /* amount */
  ) public virtual override returns (bool) {
    revert('Vester: non-transferrable');
  }

  function getVestedAmount(address _account) public view override returns (uint256) {
    uint256 balance = balances[_account];
    uint256 cumulativeClaimAmount = cumulativeClaimAmounts[_account];
    return balance + cumulativeClaimAmount;
  }

  function _mint(address _account, uint256 _amount) private {
    require(_account != address(0), 'Vester: mint to the zero address');

    totalSupply = totalSupply + _amount;
    balances[_account] = balances[_account] + _amount;

    emit Transfer(address(0), _account, _amount);
  }

  function _mintPair(address _account, uint256 _amount) private {
    require(_account != address(0), 'Vester: mint to the zero address');

    pairSupply = pairSupply + _amount;
    pairAmounts[_account] = pairAmounts[_account] + _amount;

    emit PairTransfer(address(0), _account, _amount);
  }

  function _burn(address _account, uint256 _amount) private {
    require(_account != address(0), 'Vester: burn from the zero address');
    require(_amount <= balances[_account], 'Vester: burn amount exceeds balance');

    balances[_account] = balances[_account] - _amount;
    totalSupply = totalSupply - _amount;

    emit Transfer(_account, address(0), _amount);
  }

  function _burnPair(address _account, uint256 _amount) private {
    require(_account != address(0), 'Vester: burn from the zero address');
    require(_amount <= pairAmounts[_account], 'Vester: burn amount exceeds balance');

    pairAmounts[_account] = pairAmounts[_account] - _amount;
    pairSupply = pairSupply - _amount;

    emit PairTransfer(_account, address(0), _amount);
  }

  function _deposit(address _account, uint256 _amount) private {
    require(_amount > 0, 'Vester: invalid _amount');

    _updateVesting(_account);

    IERC20(esToken).safeTransferFrom(_account, address(this), _amount);

    _mint(_account, _amount);

    if (hasPairToken()) {
      uint256 pairAmount = pairAmounts[_account];
      uint256 nextPairAmount = getPairAmount(_account, balances[_account]);
      if (nextPairAmount > pairAmount) {
        uint256 pairAmountDiff = nextPairAmount - pairAmount;
        IERC20(pairToken).safeTransferFrom(_account, address(this), pairAmountDiff);
        _mintPair(_account, pairAmountDiff);
      }
    }

    if (hasMaxVestableAmount) {
      uint256 maxAmount = getMaxVestableAmount(_account);
      require(getTotalVested(_account) <= maxAmount, 'Vester: max vestable amount exceeded');
    }

    emit Deposit(_account, _amount);
  }

  function _updateVesting(address _account) private {
    uint256 amount = _getNextClaimableAmount(_account);
    lastVestingTimes[_account] = block.timestamp;

    if (amount == 0) {
      return;
    }

    // transfer claimableAmount from balances to cumulativeClaimAmounts
    _burn(_account, amount);
    cumulativeClaimAmounts[_account] = cumulativeClaimAmounts[_account] + amount;

    IMintable(esToken).burn(address(this), amount);
  }

  function _getNextClaimableAmount(address _account) private view returns (uint256) {
    uint256 timeDiff = block.timestamp - lastVestingTimes[_account];

    uint256 balance = balances[_account];
    if (balance == 0) {
      return 0;
    }

    uint256 vestedAmount = getVestedAmount(_account);
    uint256 claimableAmount = (vestedAmount * timeDiff) / vestingDuration;

    if (claimableAmount < balance) {
      return claimableAmount;
    }

    return balance;
  }

  function _claim(address _account, address _receiver) private returns (uint256) {
    _updateVesting(_account);
    uint256 amount = claimable(_account);
    claimedAmounts[_account] = claimedAmounts[_account] + amount;
    IERC20(claimableToken).safeTransfer(_receiver, amount);
    emit Claim(_account, amount);
    return amount;
  }
}

