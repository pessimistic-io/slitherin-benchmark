// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./Initializable.sol";
import "./ERC20Upgradeable.sol";
import "./TransferHelper.sol";
import "./IYield.sol";
import "./IRewardDistributor.sol";

contract StakingYield is IYield,Initializable,ERC20Upgradeable,OwnableUpgradeable,ReentrancyGuardUpgradeable{
  uint256 public constant PRECISION = 1e30;

  address public distributor;

  mapping (address => bool) public isDepositToken;
  mapping (address => mapping (address => uint256)) public depositBalances;
  mapping (address => uint256) public totalDepositSupply;

  uint256 public cumulativeRewardPerToken;
  mapping (address => uint256) public stakedAmounts;
  mapping (address => uint256) public claimableReward;
  mapping (address => uint256) public previousCumulatedRewardPerToken;
  mapping (address => uint256) public cumulativeRewards;
  mapping (address => uint256) public averageStakedAmounts;

  bool public inPrivateTransferMode;
  mapping(address => bool) public isHandler;


  event Stake(address fundingAccount, address account, address depositToken, uint256 amount);
  event Unstake(address account, address depositToken, uint256 amount, address receiver);
  event Claim(address receiver, uint256 amount);

  function initialize(
    string memory _name, 
    string memory _symbol,
    address _distributor,
    address[] memory _depositTokens
  ) initializer public {
    __ERC20_init(_name, _symbol);
    __Ownable_init();
    __ReentrancyGuard_init();
    distributor = _distributor;
    inPrivateTransferMode = true;
    for (uint256 i = 0; i < _depositTokens.length; i++) {
      address depositToken = _depositTokens[i];
      isDepositToken[depositToken] = true;
    }
  }

  function setInPrivateTransferMode(bool _inPrivateTransferMode) external onlyOwner {
    inPrivateTransferMode = _inPrivateTransferMode;
  }
  function setHandler(address _handler, bool _active) external onlyOwner {
    isHandler[_handler] = _active;
  }

  function setDepositToken(address _depositToken, bool _isDepositToken) external onlyOwner {
    isDepositToken[_depositToken] = _isDepositToken;
  }

  function stake(address _depositToken, uint256 _amount) external nonReentrant{
    _claim(msg.sender, msg.sender);
    _stake(msg.sender, msg.sender, _depositToken, _amount);
  }
  
  function unstake(address _depositToken, uint256 _amount) external nonReentrant{
    _claim(msg.sender, msg.sender);
    _unstake(msg.sender, _depositToken, _amount, msg.sender);
  }

  function claim(address _receiver) external nonReentrant returns (uint256) {
    return _claim(msg.sender, _receiver);
  }

  function rewardToken() public view returns (address) {
    return IRewardDistributor(distributor).rewardToken();
  }
  function _claim(address _account, address _receiver) private returns (uint256) {
    _updateRewards(_account);

    uint256 tokenAmount = claimableReward[_account];
    claimableReward[_account] = 0;

    if (tokenAmount > 0) {
      TransferHelper.safeTransfer(rewardToken(), _receiver, tokenAmount);
      emit Claim(_account, tokenAmount);
    }

    return tokenAmount;
  }

  function _stake(address _fundingAccount, address _account, address _depositToken, uint256 _amount) private{
    require(_amount > 0, "Staking: invalid amount");
    require(isDepositToken[_depositToken], "Staking: invalid depositToken");

    TransferHelper.safeTransferFrom(_depositToken, _fundingAccount, address(this), _amount);
    _updateRewards(_account);
    stakedAmounts[_account] = stakedAmounts[_account] + _amount;
    depositBalances[_account][_depositToken] = depositBalances[_account][_depositToken] + _amount;
    totalDepositSupply[_depositToken] = totalDepositSupply[_depositToken] + _amount;

    _mint(_account, _amount);

    emit Stake(_fundingAccount, _account, _depositToken, _amount);
  }

  function _unstake(address _account, address _depositToken, uint256 _amount, address _receiver) private {
    require(_amount > 0, "Staking: invalid amount");
    require(isDepositToken[_depositToken], "Staking: invalid depositToken");

    _updateRewards(_account);
    require(stakedAmounts[_account] >= _amount, "Staking: amount exceeds stakedAmount");
    stakedAmounts[_account] = stakedAmounts[_account] - _amount;
    
    uint256 depositBalance = depositBalances[_account][_depositToken];
    require(depositBalance >= _amount, "Staking: amount exceeds depositBalance");
    depositBalances[_account][_depositToken] = depositBalance - _amount;
    totalDepositSupply[_depositToken] = totalDepositSupply[_depositToken] - _amount;

    _burn(_account, _amount);
    TransferHelper.safeTransfer(_depositToken, _receiver, _amount);

    emit Unstake(_account, _depositToken, _amount, _receiver);
  }

  function updateRewards() external override nonReentrant {
    _updateRewards(address(0));
  }

  function updateRewardsFor(address _account) external nonReentrant{
    _updateRewards(_account);
  }

  function estimateClaimableReward(address _account) public view returns(uint256){
    uint256 accountReward = stakedAmounts[_account] * (cumulativeRewardPerToken - previousCumulatedRewardPerToken[_account]) / PRECISION;
    uint256 _claimableReward = claimableReward[_account] + accountReward;

    return _claimableReward;
  }

  function _updateRewards(address _account) private{
    uint256 blockReward = IRewardDistributor(distributor).distribute();
    if (totalSupply() > 0 && blockReward > 0) {
      cumulativeRewardPerToken = cumulativeRewardPerToken + (blockReward * PRECISION / totalSupply());
    }

    if (cumulativeRewardPerToken == 0) {
      return;
    }

    if (_account != address(0)) {
      uint256 stakedAmount = stakedAmounts[_account];
      uint256 accountReward = stakedAmount * (cumulativeRewardPerToken - previousCumulatedRewardPerToken[_account]) / PRECISION;
      uint256 _claimableReward = claimableReward[_account] + accountReward;
      claimableReward[_account] = _claimableReward;
      previousCumulatedRewardPerToken[_account] = cumulativeRewardPerToken;

      if (_claimableReward > 0 && stakedAmounts[_account] > 0) {
        uint256 nextCumulativeReward = cumulativeRewards[_account] + accountReward;

        averageStakedAmounts[_account] = averageStakedAmounts[_account] * cumulativeRewards[_account] / nextCumulativeReward
            + stakedAmount*accountReward/nextCumulativeReward;

        cumulativeRewards[_account] = nextCumulativeReward;
      }
    }
  }

  function _beforeTokenTransfer(address /*from*/, address /*to*/, uint256 /*amount*/) internal view override{
    if (inPrivateTransferMode) {
      require(isHandler[msg.sender], "StakingYield: msg.sender not whitelisted");
    }
  }
}

