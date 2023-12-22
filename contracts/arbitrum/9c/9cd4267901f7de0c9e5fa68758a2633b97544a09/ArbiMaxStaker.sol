// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";

import "./ERC20.sol";
import "./Ownable.sol";

contract ArbiMaxStaker is Ownable {
  ERC20 public amx;
  address public amxTosser;
  bool public unstakingEnabled;
  bool public stakingEnabled = true;
  uint public totalStaked;
  uint public usersStaking;
  uint DAY_IN_SECS = 86400;

  mapping(address => uint) public stakedAmounts;

  constructor(address _amx, address _amxTosser) {
    amx = ERC20(_amx);
    amxTosser = _amxTosser;
  }

  function stake(uint _amount) public {
    require(stakingEnabled, "Staking is disabled");
    require(_amount > 1 * 10 ** 18, "Amount must be greater than 1 AMX");
    require(amx.balanceOf(msg.sender) >= _amount, "Not enough AMX");

    amx.transferFrom(msg.sender, amxTosser, _amount);

    if(stakedAmounts[msg.sender] == 0) {
      usersStaking++;
    }
    stakedAmounts[msg.sender] += _amount;
    totalStaked += _amount;
  }

  function unstake() public {
    // unstaking will be enabled after the airdrop is done
    require(unstakingEnabled, "Unstaking is disabled");
    require(stakedAmounts[msg.sender] > 0, "No AMX to unstake");

    uint amount = stakedAmounts[msg.sender];
    stakedAmounts[msg.sender] = 0;
    totalStaked -= amount;
    amx.transfer(msg.sender, amount);
  }

  function setStakingEnabled(bool _stakingEnabled) public onlyOwner {
    stakingEnabled = _stakingEnabled;
  }

  function setUnstakingEnabled(bool _unstakingEnabled) public onlyOwner {
    unstakingEnabled = _unstakingEnabled;
  }

  function setAmxTosser(address _amxTosser) public onlyOwner {
    amxTosser = _amxTosser;
  }

  // allow withdrawing airdropped tokens
  function withdrawAny(address _token) public onlyOwner {
    ERC20 token = ERC20(_token);
    token.transfer(msg.sender, token.balanceOf(address(this)));
  }
}

