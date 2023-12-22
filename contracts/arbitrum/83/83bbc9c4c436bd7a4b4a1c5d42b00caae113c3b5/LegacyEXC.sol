// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "./Ownable.sol";
import "./Math.sol";
import "./ERC20.sol";


contract EXCLegacyToken is Ownable, ERC20("Excalibur legacy token", "lEXC") {
  using SafeMath for uint256;

  struct UserAllocation {
    uint256 amount;
    bool hasClaimed;
  }

  struct AllocationInfo {
    address account;
    uint256 amount;
  }

  mapping(address => UserAllocation) public userAllocations;
  uint256 public endTime;

  constructor(uint256 endTime_) {
    require(_currentBlockTimestamp() < endTime_, "invalid endtime");
    endTime = endTime_;
  }

  /********************************************/
  /****************** EVENTS ******************/
  /********************************************/

  event Claim(address account, uint256 amount);
  event UserAllocationsUpdated();

  /*****************************************************************/
  /******************  EXTERNAL PUBLIC FUNCTIONS  ******************/
  /*****************************************************************/

  /**
   * @dev Mint the caller's allocation
   */
  function claim() external {
    UserAllocation storage allocation = userAllocations[msg.sender];

    require(allocation.amount > 0, "claim: empty allocation");
    require(!allocation.hasClaimed, "claim: has already claimed");
    require(_currentBlockTimestamp() < endTime, "claim: endtime has been reached");

    allocation.hasClaimed = true;
    _mint(msg.sender, allocation.amount);

    emit Claim(msg.sender, allocation.amount);
  }

  /**
   * @dev Set users' allocation
   */
  function setUserAllocations(AllocationInfo[] calldata allocations) external onlyOwner {
    uint256 length = allocations.length;
    require(length > 0, "setUserAllocations: invalid array");

    for (uint256 i; i < length; ++i) {
      address account = allocations[i].account;
      uint256 amount = allocations[i].amount;

      if (amount > 0 && account != address(0)) {
        userAllocations[account].amount = amount;
      }
    }

    emit UserAllocationsUpdated();
  }

  /**
   * @dev Utility function to get the current block timestamp
   */
  function _currentBlockTimestamp() internal view virtual returns (uint256) {
    /* solhint-disable not-rely-on-time */
    return block.timestamp;
  }

}

