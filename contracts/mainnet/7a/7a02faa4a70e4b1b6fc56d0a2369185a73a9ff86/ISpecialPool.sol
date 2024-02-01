//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

interface ISpecialPool { 
  enum PoolStatus {
    Inprogress,    
    Cancelled,
    Collected,
    Allowed 
  }
  enum PoolTier {
    Nothing,
    Gold,
    Platinum,
    Diamond,
    Alpha
  }
  struct PoolModel {
    uint256 hardCap; // how much project wants to raise
    uint256 softCap; // how much of the raise will be accepted as successful IDO
    uint256 specialSaleRate;
    address projectTokenAddress; //the address of the token that project is offering in return   
    PoolStatus status; //: by default “Upcoming”,
    uint256 startDateTime;
    uint256 endDateTime;
    uint256 minAllocationPerUser;
    uint256 maxAllocationPerUser;   
  }

  struct PoolDetails {     
    string extraData;
    bool whitelistable;
    bool audit;
    string auditLink;
    PoolTier tier;
    bool kyc;
  }

  struct UserVesting{
    bool isVesting;
    uint256 firstPercent;
    uint256 eachPercent;
    uint256 eachPeriod;
  }
  function sendToken(address tokenAddress, uint256 amount, address recipient) external returns (bool);
  function sendETH(uint256 amount, address recipient) external returns (bool);
  receive() external payable;
}

