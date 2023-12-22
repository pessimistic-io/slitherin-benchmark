// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ManagerAction.sol";

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
  function tokenALendingPool() external view returns (address);
  function tokenBLendingPool() external view returns (address);
  function positionId() external view returns (uint256);
  function spNft() external view returns (address);
  function work(
    ManagerAction _action,
    WorkData calldata _data
  ) external;
  function compound(bytes calldata data) external;
  function rebalance(ManagerAction _action, bytes calldata data) external;
  function allocate(bytes calldata data) external;
  function deallocate(bytes calldata data) external;
  function redeem(uint256 amt, uint256 redeemDuration) external;
  function finalizeRedeem() external;
  function updateKeeper(address _keeper, bool _approval) external;
}

