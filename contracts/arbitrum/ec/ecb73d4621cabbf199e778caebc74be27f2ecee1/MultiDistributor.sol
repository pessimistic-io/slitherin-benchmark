// SPDX-License-Identifier: ISC
pragma solidity 0.7.5;
pragma abicoder v2;

import { IERC20 } from "./IERC20.sol";
import { Ownable } from "./Ownable.sol";

contract MultiDistributor is Ownable {
  struct UserAmounts {
    address user;
    uint256 amount;
  }

  struct UserTokenAmounts {
    address user;
    IERC20 token;
    uint256 amount;
  }

  mapping(address => mapping(IERC20 => uint256)) public claimableBalances;
  mapping(address => mapping(IERC20 => uint256)) public totalClaimed;

  constructor() Ownable() {}

  function addToClaims(
    UserAmounts[] memory claimsToAdd,
    IERC20 tokenAddress,
    uint256 epochTimestamp,
    string memory tag
  ) external onlyOwner {
    for (uint256 i = 0; i < claimsToAdd.length; i++) {
      UserAmounts memory claimToAdd = claimsToAdd[i];
      claimableBalances[claimToAdd.user][tokenAddress] += claimToAdd.amount;
      require(claimableBalances[claimToAdd.user][tokenAddress] >= claimToAdd.amount, "Addition overflow for balance");
      emit ClaimAdded(tokenAddress, claimToAdd.user, claimToAdd.amount, epochTimestamp, tag);
    }
  }

  function removeClaims(address[] memory addresses, IERC20[] memory tokens) external onlyOwner {
    for (uint256 i = 0; i < addresses.length; i++) {
      for (uint256 j = 0; j < tokens.length; j++) {
        uint256 balanceToClaim = claimableBalances[addresses[i]][tokens[j]];
        claimableBalances[addresses[i]][tokens[j]] = 0;
        emit ClaimRemoved(tokens[j], addresses[i], balanceToClaim);
      }
    }
  }

  function claim(IERC20[] memory tokens) external {
    for (uint256 j = 0; j < tokens.length; j++) {
      uint256 balanceToClaim = claimableBalances[msg.sender][tokens[j]];

      if (balanceToClaim == 0) {
        continue;
      }

      claimableBalances[msg.sender][tokens[j]] = 0;
      totalClaimed[msg.sender][tokens[j]] += balanceToClaim;

      tokens[j].transfer(msg.sender, balanceToClaim);

      emit Claimed(tokens[j], msg.sender, balanceToClaim);
    }
  }

  function getClaimableForAddresses(
    address[] memory addresses,
    IERC20[] memory tokens
  ) external view returns (UserTokenAmounts[] memory claimed, UserTokenAmounts[] memory claimable) {
    claimable = new UserTokenAmounts[](addresses.length * tokens.length);
    claimed = new UserTokenAmounts[](addresses.length * tokens.length);
    for (uint256 i = 0; i < addresses.length; i++) {
      for (uint256 j = 0; j < tokens.length; j++) {
        claimed[i * tokens.length + j] = UserTokenAmounts({
          user: addresses[i],
          token: tokens[j],
          amount: totalClaimed[addresses[i]][tokens[j]]
        });
        claimable[i * tokens.length + j] = UserTokenAmounts({
          user: addresses[i],
          token: tokens[j],
          amount: claimableBalances[addresses[i]][tokens[j]]
        });
      }
    }
  }

  //////
  // Events
  event Claimed(IERC20 indexed rewardToken, address indexed claimer, uint256 amount);
  event ClaimAdded(
    IERC20 indexed rewardToken,
    address indexed claimer,
    uint256 amount,
    uint256 indexed epochTimestamp,
    string tag
  );
  event ClaimRemoved(IERC20 indexed rewardToken, address indexed claimer, uint256 amount);
}

