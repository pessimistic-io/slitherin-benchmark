// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./IERC20.sol";
import { IWhitelist } from "./Whitelist.sol";
import { IPlsRdntPlutusChef, IRdntLpStaker, IPlsRdntRewardsDistro } from "./Interfaces.sol";
import { IProtocolRewardsHandler } from "./Radiant.sol";

contract PlsRdntPlutusChef is
  IPlsRdntPlutusChef,
  Initializable,
  PausableUpgradeable,
  Ownable2StepUpgradeable,
  UUPSUpgradeable
{
  struct UserInfo {
    uint96 amount;
    int128 plsRewardDebt;
    int128 wethRewardDebt;
    int128 wbtcRewardDebt;
    int128 usdcRewardDebt;
    int128 usdtRewardDebt;
    int128 daiRewardDebt;
    int128 arbRewardDebt;
    int128 wstethRewardDebt;
  }

  struct RewardTokens {
    uint128 pls;
    uint128 wbtc;
    uint128 usdt;
    uint128 usdc;
    uint128 dai;
    uint128 weth;
    uint128 arb;
    uint128 wsteth;
  }

  uint256 private constant MUL_CONSTANT = 1e24;
  address public constant PLS = 0x51318B7D00db7ACc4026C88c3952B66278B6A67F;
  IERC20 public constant STAKING_TOKEN = IERC20(0x1605bbDAB3b38d10fA23A7Ed0d0e8F4FEa5bFF59);
  uint public constant REWARD_COUNT = 8;

  uint128 public acc_pls_PerShare;
  uint128 public acc_wbtc_PerShare;
  uint128 public acc_usdt_PerShare;
  uint128 public acc_usdc_PerShare;
  uint128 public acc_dai_PerShare;
  uint128 public acc_weth_PerShare;

  uint128 public plsPerSecond;
  uint96 public shares;
  uint32 public lastRewardSecond;

  IWhitelist public whitelist;
  IPlsRdntRewardsDistro public distro;
  mapping(address => UserInfo) public userInfo;
  mapping(address => bool) private handlers;

  uint128 public acc_arb_PerShare;
  uint128 public acc_wsteth_PerShare;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(uint32 _rewardEmissionStart) public initializer {
    __Pausable_init();
    __Ownable2Step_init();
    __UUPSUpgradeable_init();
    lastRewardSecond = _rewardEmissionStart;
  }

  function deposit(uint96 _amount) external {
    revert FAILED('PlutusChef: Deprecated');
    _isEligibleSender();
    _deposit(msg.sender, msg.sender, _amount);
  }

  function withdraw(uint96 _amount) external {
    _isEligibleSender();
    _withdraw(msg.sender, _amount);
  }

  function harvest() external {
    _isEligibleSender();
    _harvest(msg.sender);
  }

  function emergencyWithdraw() external {
    _isEligibleSender();
    UserInfo storage user = userInfo[msg.sender];

    uint96 _amount = user.amount;

    user.amount = 0;
    user.plsRewardDebt = 0;
    user.wethRewardDebt = 0;
    user.wbtcRewardDebt = 0;
    user.usdcRewardDebt = 0;
    user.usdtRewardDebt = 0;
    user.daiRewardDebt = 0;
    user.arbRewardDebt = 0;
    user.wstethRewardDebt = 0;

    if (shares >= _amount) {
      shares -= _amount;
    } else {
      shares = 0;
    }

    STAKING_TOKEN.transfer(msg.sender, _amount);
    emit EmergencyWithdraw(msg.sender, _amount);
  }

  function updateShares() public whenNotPaused {
    if (block.timestamp <= lastRewardSecond) {
      return;
    }

    if (shares == 0) {
      lastRewardSecond = uint32(block.timestamp);
      return;
    }

    if (distro.hasBufferedRewards()) {
      IProtocolRewardsHandler.RewardData[] memory _rewards = distro.record();
      _incrementRewardsAccPerShare(_rewards);
    }

    unchecked {
      acc_pls_PerShare += rewardPerShare(plsPerSecond);
    }

    lastRewardSecond = uint32(block.timestamp);
  }

  /** VIEWS */
  /**
    Calculates the reward per share since `lastRewardSecond` was updated
  */
  function rewardPerShare(uint _rewardRatePerSecond) public view returns (uint128) {
    unchecked {
      uint _pendingRewards = (block.timestamp - lastRewardSecond) * _rewardRatePerSecond;
      return uint128((_pendingRewards * MUL_CONSTANT) / shares);
    }
  }

  function pendingRewards(address _user) external view returns (RewardTokens memory _pendingRewards) {
    IProtocolRewardsHandler.RewardData[] memory _rewards = distro.pendingRewards();
    uint _len = _rewards.length;
    uint _shares = shares;

    RewardTokens memory _accPerShare = RewardTokens({
      pls: acc_pls_PerShare,
      wbtc: acc_wbtc_PerShare,
      usdt: acc_usdt_PerShare,
      usdc: acc_usdc_PerShare,
      dai: acc_dai_PerShare,
      weth: acc_weth_PerShare,
      arb: acc_arb_PerShare,
      wsteth: acc_wsteth_PerShare
    });

    if (_shares != 0) {
      if (block.timestamp > lastRewardSecond) {
        _accPerShare.pls += rewardPerShare(plsPerSecond);
      }

      // update reward tokens acc per share
      for (uint i; i < _len; i = _unsafeInc(i)) {
        address _rewardToken = _rewards[i].token;
        if (_rewardToken == address(0) || _rewards[i].amount == 0) continue;
        uint128 _rewardPerShare = uint128((_rewards[i].amount * MUL_CONSTANT) / _shares);

        if (_rewardToken == 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f) {
          _accPerShare.wbtc += _rewardPerShare; // WBTC
        } else if (_rewardToken == 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9) {
          _accPerShare.usdt += _rewardPerShare; // USDT
        } else if (_rewardToken == 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8) {
          _accPerShare.usdc += _rewardPerShare; // USDC
        } else if (_rewardToken == 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1) {
          _accPerShare.dai += _rewardPerShare; // DAI
        } else if (_rewardToken == 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1) {
          _accPerShare.weth += _rewardPerShare; // WETH
        } else if (_rewardToken == 0x912CE59144191C1204E64559FE8253a0e49E6548) {
          _accPerShare.arb += _rewardPerShare; // ARB
        } else if (_rewardToken == 0x5979D7b546E38E414F7E9822514be443A4800529) {
          _accPerShare.wsteth += _rewardPerShare; // WSTETH
        } else {
          revert FAILED('Unreachable');
        }
      }
    }

    UserInfo memory user = userInfo[_user];
    uint96 _userDepositAmount = user.amount;

    _pendingRewards = RewardTokens({
      pls: _calculatePending(user.plsRewardDebt, _accPerShare.pls, _userDepositAmount),
      wbtc: _calculatePending(user.wbtcRewardDebt, _accPerShare.wbtc, _userDepositAmount),
      usdt: _calculatePending(user.usdtRewardDebt, _accPerShare.usdt, _userDepositAmount),
      usdc: _calculatePending(user.usdcRewardDebt, _accPerShare.usdc, _userDepositAmount),
      dai: _calculatePending(user.daiRewardDebt, _accPerShare.dai, _userDepositAmount),
      weth: _calculatePending(user.wethRewardDebt, _accPerShare.weth, _userDepositAmount),
      arb: _calculatePending(user.arbRewardDebt, _accPerShare.arb, _userDepositAmount),
      wsteth: _calculatePending(user.wstethRewardDebt, _accPerShare.wsteth, _userDepositAmount)
    });
  }

  /** PRIVATE */
  function _isEligibleSender() private view {
    if (msg.sender != tx.origin && whitelist.isWhitelisted(msg.sender) == false) revert UNAUTHORIZED();
  }

  function _calculatePending(
    int128 _rewardDebt,
    uint256 _accTokenPerShare, // Stay 256;
    uint96 _amount
  ) private pure returns (uint128) {
    if (_rewardDebt < 0) {
      return uint128(_calculateRewardDebt(_accTokenPerShare, _amount)) + uint128(-_rewardDebt);
    } else {
      return uint128(_calculateRewardDebt(_accTokenPerShare, _amount)) - uint128(_rewardDebt);
    }
  }

  function _deposit(address _from, address _user, uint96 _amount) private {
    UserInfo storage user = userInfo[_user];
    if (_amount < 1 ether) revert DEPOSIT_ERROR('min deposit: 1 plsRDNT');
    updateShares();

    uint256 _prev = STAKING_TOKEN.balanceOf(address(this));

    unchecked {
      user.amount += _amount;
      shares += _amount;
    }

    _incrementDebt(user, _amount);
    STAKING_TOKEN.transferFrom(_from, address(this), _amount);

    unchecked {
      if (_prev + _amount != STAKING_TOKEN.balanceOf(address(this))) revert DEPOSIT_ERROR('invariant violation');
    }

    emit Deposit(_user, _amount);
  }

  function _withdraw(address _user, uint96 _amount) private {
    UserInfo storage user = userInfo[_user];
    if (user.amount < _amount || _amount == 0) revert WITHDRAW_ERROR();
    updateShares();

    unchecked {
      user.amount -= _amount;
      shares -= _amount;
    }

    _decrementDebt(user, _amount);
    STAKING_TOKEN.transfer(_user, _amount);
    emit Withdraw(_user, _amount);
  }

  function _getTransferrableRewards(
    UserInfo storage user
  ) private view returns (IProtocolRewardsHandler.RewardData[] memory _transferrableRewards) {
    uint96 _userDepositAmount = user.amount;

    _transferrableRewards = new IProtocolRewardsHandler.RewardData[](REWARD_COUNT);
    _transferrableRewards[0] = IProtocolRewardsHandler.RewardData({
      token: PLS,
      amount: _calculatePending(user.plsRewardDebt, acc_pls_PerShare, _userDepositAmount)
    });
    _transferrableRewards[1] = IProtocolRewardsHandler.RewardData({
      token: 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f, // WBTC
      amount: _calculatePending(user.wbtcRewardDebt, acc_wbtc_PerShare, _userDepositAmount)
    });
    _transferrableRewards[2] = IProtocolRewardsHandler.RewardData({
      token: 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, // USDT
      amount: _calculatePending(user.usdtRewardDebt, acc_usdt_PerShare, _userDepositAmount)
    });
    _transferrableRewards[3] = IProtocolRewardsHandler.RewardData({
      token: 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8, // USDC
      amount: _calculatePending(user.usdcRewardDebt, acc_usdc_PerShare, _userDepositAmount)
    });
    _transferrableRewards[4] = IProtocolRewardsHandler.RewardData({
      token: 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1, // DAI
      amount: _calculatePending(user.daiRewardDebt, acc_dai_PerShare, _userDepositAmount)
    });
    _transferrableRewards[5] = IProtocolRewardsHandler.RewardData({
      token: 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1, // WETH
      amount: _calculatePending(user.wethRewardDebt, acc_weth_PerShare, _userDepositAmount)
    });
    _transferrableRewards[6] = IProtocolRewardsHandler.RewardData({
      token: 0x912CE59144191C1204E64559FE8253a0e49E6548, // ARB
      amount: _calculatePending(user.arbRewardDebt, acc_arb_PerShare, _userDepositAmount)
    });
    _transferrableRewards[7] = IProtocolRewardsHandler.RewardData({
      token: 0x5979D7b546E38E414F7E9822514be443A4800529, // WSTETH
      amount: _calculatePending(user.wstethRewardDebt, acc_wsteth_PerShare, _userDepositAmount)
    });
  }

  function _harvest(address _user) private {
    updateShares();
    UserInfo storage user = userInfo[_user];
    IProtocolRewardsHandler.RewardData[] memory _transferrableRewards = _getTransferrableRewards(user);

    _setDebt(user); // needs to be AFTER _getTransferrableRewards
    distro.sendRewards(_user, _transferrableRewards);
  }

  function _calculateRewardDebt(uint256 _accTokenPerShare, uint256 _amount) private pure returns (uint256) {
    unchecked {
      return (_amount * _accTokenPerShare) / MUL_CONSTANT;
    }
  }

  function _incrementRewardsAccPerShare(IProtocolRewardsHandler.RewardData[] memory rewards) private {
    uint _rewardsCount = rewards.length;
    uint _shares = shares;

    for (uint i; i < _rewardsCount; i = _unsafeInc(i)) {
      address _rewardToken = rewards[i].token;
      if (_rewardToken == address(0) || rewards[i].amount == 0) continue;

      uint128 _rewardPerShare = uint128((rewards[i].amount * MUL_CONSTANT) / _shares);

      if (_rewardToken == 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f) {
        acc_wbtc_PerShare += _rewardPerShare; // WBTC
      } else if (_rewardToken == 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9) {
        acc_usdt_PerShare += _rewardPerShare; // USDT
      } else if (_rewardToken == 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8) {
        acc_usdc_PerShare += _rewardPerShare; // USDC
      } else if (_rewardToken == 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1) {
        acc_dai_PerShare += _rewardPerShare; // DAI
      } else if (_rewardToken == 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1) {
        acc_weth_PerShare += _rewardPerShare; // WETH
      } else if (_rewardToken == 0x912CE59144191C1204E64559FE8253a0e49E6548) {
        acc_arb_PerShare += _rewardPerShare; // ARB
      } else if (_rewardToken == 0x5979D7b546E38E414F7E9822514be443A4800529) {
        acc_wsteth_PerShare += _rewardPerShare; // WSTETH
      } else {
        revert FAILED('Unreachable');
      }
    }
  }

  function _unsafeInc(uint x) private pure returns (uint) {
    unchecked {
      return x + 1;
    }
  }

  function _incrementDebt(UserInfo storage user, uint _amount) private {
    user.plsRewardDebt += int128(uint128(_calculateRewardDebt(acc_pls_PerShare, _amount)));
    user.wethRewardDebt += int128(uint128(_calculateRewardDebt(acc_weth_PerShare, _amount)));
    user.wbtcRewardDebt += int128(uint128(_calculateRewardDebt(acc_wbtc_PerShare, _amount)));
    user.daiRewardDebt += int128(uint128(_calculateRewardDebt(acc_dai_PerShare, _amount)));
    user.usdcRewardDebt += int128(uint128(_calculateRewardDebt(acc_usdc_PerShare, _amount)));
    user.usdtRewardDebt += int128(uint128(_calculateRewardDebt(acc_usdt_PerShare, _amount)));
    user.arbRewardDebt += int128(uint128(_calculateRewardDebt(acc_arb_PerShare, _amount)));
    user.wstethRewardDebt += int128(uint128(_calculateRewardDebt(acc_wsteth_PerShare, _amount)));
  }

  function _decrementDebt(UserInfo storage user, uint _amount) private {
    user.plsRewardDebt -= int128(uint128(_calculateRewardDebt(acc_pls_PerShare, _amount)));
    user.wethRewardDebt -= int128(uint128(_calculateRewardDebt(acc_weth_PerShare, _amount)));
    user.wbtcRewardDebt -= int128(uint128(_calculateRewardDebt(acc_wbtc_PerShare, _amount)));
    user.daiRewardDebt -= int128(uint128(_calculateRewardDebt(acc_dai_PerShare, _amount)));
    user.usdcRewardDebt -= int128(uint128(_calculateRewardDebt(acc_usdc_PerShare, _amount)));
    user.usdtRewardDebt -= int128(uint128(_calculateRewardDebt(acc_usdt_PerShare, _amount)));
    user.arbRewardDebt -= int128(uint128(_calculateRewardDebt(acc_arb_PerShare, _amount)));
    user.wstethRewardDebt -= int128(uint128(_calculateRewardDebt(acc_wsteth_PerShare, _amount)));
  }

  function _setDebt(UserInfo storage user) private {
    user.plsRewardDebt = int128(uint128(_calculateRewardDebt(acc_pls_PerShare, user.amount)));
    user.wethRewardDebt = int128(uint128(_calculateRewardDebt(acc_weth_PerShare, user.amount)));
    user.wbtcRewardDebt = int128(uint128(_calculateRewardDebt(acc_wbtc_PerShare, user.amount)));
    user.daiRewardDebt = int128(uint128(_calculateRewardDebt(acc_dai_PerShare, user.amount)));
    user.usdcRewardDebt = int128(uint128(_calculateRewardDebt(acc_usdc_PerShare, user.amount)));
    user.usdtRewardDebt = int128(uint128(_calculateRewardDebt(acc_usdt_PerShare, user.amount)));
    user.arbRewardDebt = int128(uint128(_calculateRewardDebt(acc_arb_PerShare, user.amount)));
    user.wstethRewardDebt = int128(uint128(_calculateRewardDebt(acc_wsteth_PerShare, user.amount)));
  }

  /** HANDLER */
  function depositFor(address _user, uint96 _amount) external {
    if (handlers[msg.sender] == false) revert UNAUTHORIZED();
    _deposit(msg.sender, _user, _amount);
  }

  function withdrawFor(address _user, uint96 _amount) external {
    if (handlers[msg.sender] == false) revert UNAUTHORIZED();
    _withdraw(_user, _amount);
  }

  function harvestFor(address _user) external {
    if (handlers[msg.sender] == false) revert UNAUTHORIZED();
    _harvest(_user);
  }

  /** OWNER FUNCTIONS */
  function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

  function setWhitelist(address _whitelist) external onlyOwner {
    whitelist = IWhitelist(_whitelist);
  }

  function updateHandler(address _handler, bool _isActive) external onlyOwner {
    handlers[_handler] = _isActive;
    emit HandlerUpdated(_handler, _isActive);
  }

  function setEmission(uint128 _plsPerSecond) external onlyOwner {
    plsPerSecond = _plsPerSecond;
  }

  function setDistro(address _distro) external onlyOwner {
    distro = IPlsRdntRewardsDistro(_distro);
  }

  function setStartTime(uint32 _startTime) external onlyOwner {
    lastRewardSecond = _startTime;
  }

  function setPaused(bool _pauseContract) external onlyOwner {
    if (_pauseContract) {
      _pause();
    } else {
      _unpause();
    }
  }
}

