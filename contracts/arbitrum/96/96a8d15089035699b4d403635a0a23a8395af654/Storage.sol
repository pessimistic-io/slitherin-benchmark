//contracts/Organizer.sol
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title Storage for Organizer Contract

abstract contract Storage {
  /*
    Orgs Struct
    approverCount : number of approvers in a Dao
    approvers: mapping of addresses of Approver
    approvalMatrices: mapping(tokenAddress => ApprovalMatrix)
    claimables: mapping(tokenAddress => contributorAddress => amount)
    autoClaim: mapping(contributorAddress => isEnabled)
  */

  struct ORG {
    uint256 approverCount;
    mapping(address => address) approvers;
    mapping(address => ApprovalLevel[]) approvalMatrices;
    mapping(address => mapping(address => uint96)) claimables;
    mapping(address => bool) autoClaim;
  }

  address ALLOWANCE_MODULE;

  /*
    ApprovalLevel Struct
    minAmount : minimun amount value of the Range
    maxAmount: maximum amount value of the Range
    approvalsRequired: numbers of approval required if amount fall within this range
   
  */
  struct ApprovalLevel {
    uint256 minAmount;
    uint256 maxAmount;
    uint256 maxAggregattedAmount;
    uint256 currentSpendedAmount;
    uint8 approvalsRequired;
  }

  /*
    Payout Struct
    isValidate : If Payout has matching number of approvals
    isExecuted: If Transfer has already been made to Contributor Address
    approvals: mapping(approverAddres => isApproved)
    approvalCount: Number of approvals Added to the Payout
  */
  struct Payout {
    bool isValidated;
    bool isExecuted;
    mapping(address => bool) approvals;
    uint256 approvalCount;
  }

  // Enum for Operation
  enum Operation {
    Call,
    DelegateCall
  }

  //  Sentinel to use with linked lists
  address internal constant SENTINEL_ADDRESS = address(0x1);
  address internal MASTER_OPERATOR;
  uint256 internal constant SENTINEL_UINT = 1;

  /*
    Daos mapping
    mapping(safeAddress => struct ORG); 
  */
  mapping(address => ORG) orgs;

  /*
    Payouts mapping
    mapping(payoutNonce => struct Payout); 
  */
  mapping(uint256 => Payout) public payouts;
}

