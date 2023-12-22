// SPDX-License-Identifier: BUSL-1.1
// This code is made available under the terms and conditions of the Business Source License 1.1 (BUSL-1.1).
// The act of publishing this code is driven by the aim to promote transparency and facilitate its utilization for educational purposes.

pragma solidity 0.8.18;

interface IVester {
  // ---------------------
  //       Errors
  // ---------------------
  error IVester_BadArgument();
  error IVester_ExceedMaxDuration();
  error IVester_Unauthorized();
  error IVester_Claimed();
  error IVester_Aborted();
  error IVester_HasCompleted();
  error IVester_InvalidAddress();
  error IVester_PositionNotFound();
  error IVester_HMXStakingNotSet();

  // ---------------------
  //       Structs
  // ---------------------
  struct Item {
    address owner;
    bool hasClaimed;
    bool hasAborted;
    uint256 amount;
    uint256 startTime;
    uint256 endTime;
    uint256 lastClaimTime;
    uint256 totalUnlockedAmount;
  }

  function vestFor(address account, uint256 amount, uint256 duration) external;

  function claim(uint256 itemIndex) external;

  function claim(uint256[] memory itemIndexes) external;

  function abort(uint256 itemIndex) external;

  function getUnlockAmount(uint256 amount, uint256 duration) external returns (uint256);

  function itemLastIndex(address) external returns (uint256);

  function items(
    address user,
    uint256 index
  )
    external
    view
    returns (
      address owner,
      bool hasClaimed,
      bool hasAborted,
      uint256 amount,
      uint256 startTime,
      uint256 endTime,
      uint256 lastClaimTime,
      uint256 totalUnlockedAmount
    );

  function setHMXStaking(address _hmxStaking) external;
}

