// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC20.sol";

contract TimeVaultLock {

      struct LockId {
        uint256 id;
        address tokenAddress;
        uint256 lockAmount;
        address userAddress;
        uint256 expiry;
        bool wihtdrawn;
    }

    // Erorr 
  
    uint256 public lockID ;
    mapping(uint256 => LockId) public lockIDToLock;
    error TokensLocked();
    function deposit(address userAddress,address _token, uint256 _amount , uint _time) external payable {
        IERC20 token = IERC20(_token);
       
        token.transferFrom(userAddress, address(this), _amount);
        lockID=lockID+1;

        LockId memory newLock;
        newLock.id=lockID;
        newLock.tokenAddress=(_token);
        newLock.lockAmount=_amount;
        newLock.userAddress=userAddress;
        newLock.expiry=_time;
        newLock.wihtdrawn = false;
        lockIDToLock[lockID] = newLock;
       
    }

    function withdraw(uint256 _lockID) external {
        LockId storage lock = lockIDToLock[_lockID];
        require(lock.id != 0, "Lock not exists");
        require(lock.wihtdrawn == false, "Lock alreaddy withdrawn");
        require(block.timestamp > lock.expiry, "Lock not expired");
        lockIDToLock[_lockID].wihtdrawn = true;

        IERC20 token = IERC20(lock.tokenAddress);

        token.transfer(lock.userAddress, lock.lockAmount);
        
    }

    
}
