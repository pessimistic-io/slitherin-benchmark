// SPDX-License-Identifier: MIT
/**
        /\_/\
      ( o   o )
        > ^ <
 */
pragma solidity 0.8.15;

import "./Rice.sol";
import "./Barn.sol";

contract Deposit {
  Rice public immutable rice;
  Barn public immutable barn;

  struct UserInfo {
    uint256 amount;
    uint256 totalAmount;
    uint256 base_supply;
  }
  mapping(address => UserInfo) public userMap;

  event Withdraw(address indexed user, uint256 amount);

  constructor(Rice _rice, Barn _barn) {
    rice = _rice;
    barn = _barn;
  }

  function deposit(address user, uint256 amount) external {
    require(amount > 0, 'amount must be greater than 0');
    _withdraw(user);
    UserInfo storage userInfo = userMap[user];
    userInfo.amount += amount;
    userInfo.totalAmount += amount;
    userInfo.base_supply = barn.totalRiceSupply();
    rice.transferFrom(msg.sender, address(this), amount);
  }

  function pending(address account) external view returns (uint256) {
    UserInfo storage userInfo = userMap[account];
    uint256 base_supply = barn.totalRiceSupply();
    uint256 amount;
    if (userInfo.base_supply == 0) {
      amount = 0;
    } else {
      // base_supply / amount = userInfo.base_supply / userInfo.amount
      amount = (base_supply * userInfo.amount) / userInfo.base_supply;
    }
    return userInfo.amount - amount;
  }

  function withdraw() public {
    _withdraw(msg.sender);
  }

  function _withdraw(address user) internal {
    UserInfo storage userInfo = userMap[user];
    if (userInfo.amount == 0) return;

    uint256 base_supply = barn.totalRiceSupply();
    uint256 amount;

    if (userInfo.base_supply == 0) {
      amount = 0;
    } else {
      // base_supply / amount = userInfo.base_supply / userInfo.amount
      amount = (base_supply * userInfo.amount) / userInfo.base_supply;
    }
    uint256 diff = userInfo.amount - amount;

    if (diff == 0) return;

    userInfo.base_supply = base_supply;
    userInfo.amount = amount;
    rice.transfer(user, diff);
    emit Withdraw(user, diff);
  }
}

