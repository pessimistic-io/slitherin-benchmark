// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IPublicLockV9.sol";
import "./IERC20.sol";

interface IMultiFeeDistribution {
    struct LockedBalance {
        uint256 amount;
        uint256 unlockTime;
    }

    function lockedBalances(address) external view returns (uint256, uint256, uint256, LockedBalance[] memory);
}

contract ERC20BalanceOfHook {
  address public immutable multiFeeDistribution;
  mapping(address => address) public tokenAddresses;
  mapping(address => uint) public minAmounts;

  constructor(address _multiFeeDistribution) {
      multiFeeDistribution = _multiFeeDistribution;
  }

  function createMapping(
    address _lockAddress, 
    address _tokenAddress,
    uint _minAmount // minimum amount to hold
  ) 
  external 
  {
    require(_lockAddress != address(0), 'Lock address can not be zero');
    require(_tokenAddress != address(0), 'ERC20 address can not be zero');
    require(_minAmount != 0, 'minAmount can not be zero');

    // make sure lock manager
    IPublicLockV9 lock = IPublicLockV9(_lockAddress);
    require(lock.isLockManager(msg.sender), 'Caller does not have the LockManager role');
    
    // store mapping
    tokenAddresses[_lockAddress] = _tokenAddress;
    minAmounts[_lockAddress] = _minAmount;
  }

  function hasValidKey(
    address _lockAddress,
    address _keyOwner,
    uint256, // _expirationTimestamp,
    bool isValidKey
  ) 
  external view
  returns (bool)
  {
    if (isValidKey) return true;

    // get token contract 
    address tokenAddress = tokenAddresses[_lockAddress];
    if(tokenAddress == address(0)) return false;

    // get token balance
    uint minAmount = minAmounts[_lockAddress];
    (uint256 total, , , ) = IMultiFeeDistribution(multiFeeDistribution).lockedBalances(_keyOwner);
    
    return total >= minAmount;
  }

}
