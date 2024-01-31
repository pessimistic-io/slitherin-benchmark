// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Sector3DAOPriority.sol";

/**
 * When deployed, an instance of this smart contract 
 * represents a new DAO added to the Sector#3 protocol.
 */
contract Sector3DAO {

  /**
   * The protocol version.
   */
  uint8 public constant version = 1;

  /**
   * The smart contract owner.
   */
  address public owner;

  /**
   * The name of the DAO.
   */
  string public name;

  /**
   * The purpose of the DAO.
   */
  string public purpose;

  /**
   * The DAO token (e.g. governance token).
   */
  address public token;

  /**
   * The priorities added by this DAO.
   */
  Sector3DAOPriority[] public priorities;

  event PriorityDeployed(Sector3DAOPriority);

  constructor(string memory name_, string memory purpose_, address token_) {
    name = name_;
    purpose = purpose_;
    token = token_;
    owner = tx.origin;
  }

  /**
   * Updates the DAO's owner.
   */
  function setOwner(address owner_) public {
    require(msg.sender == owner, "You aren't the owner");
    owner = owner_;
  }

  /**
   * Updates the DAO's name.
   */
  function setName(string calldata name_) public {
    require(msg.sender == owner, "You aren't the owner");
    name = name_;
  }

  /**
   * Updates the DAO's purpose.
   */
  function setPurpose(string calldata purpose_) public {
    require(msg.sender == owner, "You aren't the owner");
    purpose = purpose_;
  }

  /**
   * Updates the DAO's token.
   */
  function setToken(address token_) public {
    require(msg.sender == owner, "You aren't the owner");
    token = token_;
  }

  function deployPriority(string calldata title, address rewardToken, uint16 epochDurationInDays, uint256 epochBudget, address gatingNFT) public returns (Sector3DAOPriority) {
    require(msg.sender == owner, "You aren't the owner");
    Sector3DAOPriority priority = new Sector3DAOPriority(address(this), title, rewardToken, epochDurationInDays, epochBudget, gatingNFT);
    priorities.push(priority);
    emit PriorityDeployed(priority);
    return priority;
  }

  function getPriorities() public view returns (Sector3DAOPriority[] memory) {
    return priorities;
  }

  function removePriority(Sector3DAOPriority priority) public {
    require(msg.sender == owner, "You aren't the owner");
    Sector3DAOPriority[] memory prioritiesAfterRemoval = new Sector3DAOPriority[](priorities.length - 1);
    uint16 prioritiesIndex = 0;
    for (uint16 i = 0; i < prioritiesAfterRemoval.length; i++) {
      if (priority == priorities[prioritiesIndex]) {
        prioritiesIndex++;
      }
      prioritiesAfterRemoval[i] = priorities[prioritiesIndex];
      prioritiesIndex++;
    }
    priorities = prioritiesAfterRemoval;
  }
}

