//SPDX-License-Identifier: MIT

/**
888888ba           .8888b oo dP       oo   dP                                   .d88888b    dP            dP       oo                   
88    `8b          88   "    88            88                                   88.    "'   88            88                            
88     88 .d8888b. 88aaa  dP 88d888b. dP d8888P 88d888b. dP    dP 88d8b.d8b.    `Y88888b. d8888P .d8888b. 88  .dP  dP 88d888b. .d8888b. 
88     88 88ooood8 88     88 88'  `88 88   88   88'  `88 88    88 88'`88'`88          `8b   88   88'  `88 88888"   88 88'  `88 88'  `88 
88    .8P 88.  ... 88     88 88.  .88 88   88   88       88.  .88 88  88  88    d8'   .8P   88   88.  .88 88  `8b. 88 88    88 88.  .88 
8888888P  `88888P' dP     dP 88Y8888' dP   dP   dP       `88888P' dP  dP  dP     Y88888P    dP   `88888P8 dP   `YP dP dP    dP `8888P88 
oooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo~~~~.88~
                                                                                                                                d8888P 
- Fixed-Rate (FR) Staking Model with compound interests to maximize gains
- 15% APR
- No Lock Time
*/

import "./RewardsMath.sol";
import "./ErrorReporter.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

pragma solidity ^0.8.17;

contract DFMStaking is
  ReentrancyGuard,
  Ownable,
  ErrorReporter,
  RewardCalculator
{
  using SafeERC20 for IERC20;

  //Stakers
  struct Staker {
    uint256 totalStaked;
    uint256 lastClaim;
    uint256 totalClaimed;
  }
  mapping(address => Staker) public Stakers;

  // Contract info
  string public name;
  string public symbol;

  // Token info
  address public token;

  //Events
  event Staked(uint256 amount, address indexed staker);
  event Withdraw(uint256 amount, address indexed staker);
  event Claimed(uint256 amount, address indexed staker, uint256 indexed time);

  // Staking configurations
  uint256 public immutable apr;
  uint256 public totalSupply;

  constructor(
    string memory _name,
    string memory _symbol,
    address _token,
    uint256 _apr
  ) {
    name = _name;
    symbol = _symbol;
    token = _token;
    apr = _apr;
  }

  /**
   * @param _amount amount to be staked or withdrawed
   */
  modifier nonZero(uint256 _amount) {
    if (_amount == 0) {
      revert ZeroAmount();
    }
    _;
  }

  /**
   * @param _staker address of staker to calculate rewards in the elapsed
   */
  function getUnclaimedRewards(
    address _staker
  ) public view returns (uint256 totalRewards) {
    Staker storage staker = Stakers[_staker];
    uint256 principal = staker.totalStaked;
    uint256 elapsedTime = block.timestamp - staker.lastClaim;
    uint256 rewards = calculateInteresetInSeconds(principal, apr, elapsedTime);
    totalRewards = rewards > principal ? rewards - principal : 0;
  }

  // Claiming rewards
  function claimRewards() public {
    Staker storage staker = Stakers[msg.sender];
    uint256 rewards = getUnclaimedRewards(msg.sender);
    if (staker.totalStaked == 0 || rewardPoolSize() < rewards || rewards == 0) {
      return;
    }
    IERC20(token).safeTransfer(msg.sender, rewards); //send the rewards to staker
    staker.lastClaim = block.timestamp;
    staker.totalClaimed += rewards;
    emit Claimed(rewards, msg.sender, block.timestamp);
  }

  /**
   * @param _amount  amount to be staked
   */
  function stake(uint256 _amount) public nonZero(_amount) nonReentrant {
    claimRewards();
    Staker storage staker = Stakers[msg.sender];
    IERC20(token).safeTransferFrom(msg.sender, address(this), _amount);
    staker.lastClaim = block.timestamp;
    staker.totalStaked += _amount;
    totalSupply += _amount;
    emit Staked(_amount, msg.sender);
  }

  /**
   * @param _amount amount to withdraw
   */
  function withdraw(uint256 _amount) public nonZero(_amount) nonReentrant {
    claimRewards();
    Staker storage staker = Stakers[msg.sender];
    if (staker.totalStaked < _amount) {
      revert NotEnoughBalance();
    }
    staker.totalStaked -= _amount;
    staker.lastClaim = block.timestamp;
    totalSupply -= _amount;
    IERC20(token).safeTransfer(msg.sender, _amount);
    emit Withdraw(_amount, msg.sender);
  }

  /**
   * Calucates the reward pool size (the tokens that are going to be given as rewards)
   */
  function rewardPoolSize() public view returns (uint256) {
    uint256 balance = IERC20(token).balanceOf(address(this));
    return balance - totalSupply;
  }

  /**
   * @param _token the token address that is going to be withdrawed
   * @param _receiver receiver of the tokens
   */
  function withdrawTokens(address _token, address _receiver) public onlyOwner {
    if (_token == token) {
      IERC20(_token).safeTransfer(_receiver, rewardPoolSize());
    } else {
      IERC20(_token).safeTransfer(
        _receiver,
        IERC20(_token).balanceOf(address(this))
      );
    }
  }

  /**
   * used to withdraw tokens
   */
  function withdrawETH() public onlyOwner {
    (bool sucecss, ) = msg.sender.call{value: address(this).balance}("");
    require(sucecss, "transferring ETH failed");
  }

  function approveSpender(address _spender, address _token) public onlyOwner {
    IERC20(_token).approve(_spender, ~uint256(0));
  }

  function getTotalStaked(address _staker) public view returns (uint256) {
    return Stakers[_staker].totalStaked;
  }
}

