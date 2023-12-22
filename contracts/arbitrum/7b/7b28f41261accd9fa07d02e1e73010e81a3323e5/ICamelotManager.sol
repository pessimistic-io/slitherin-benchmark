// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ManagerAction.sol";
import "./ILendingPool.sol";

interface ICamelotManager {
  struct WorkData {
    address token;
    uint256 lpAmt;
    uint256 borrowTokenAAmt;
    uint256 borrowTokenBAmt;
    uint256 repayTokenAAmt;
    uint256 repayTokenBAmt;
  }
  function lpToken() external view returns (address);
  function tokenALendingPool() external view returns (ILendingPool);
  function tokenBLendingPool() external view returns (ILendingPool);
  function positionId() external view returns (uint256);
  function spNft() external view returns (address);
  function work(
    ManagerAction action,
    WorkData calldata _data
  ) external;
  function compound(bytes calldata data) external;
  function rebalance(ManagerAction action, WorkData calldata data) external;
  function allocate(uint256 action, bytes calldata data) external;
  function redeem(uint256 amt, uint256 redeemDuration) external;
  function finalizeRedeem(uint256 index) external;
  function updateKeeper(address _keeper, bool _approval) external;
}

