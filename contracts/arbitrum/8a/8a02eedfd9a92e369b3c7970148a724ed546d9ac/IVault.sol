// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.16;

import "./IERC4626.sol";

interface IVault is IERC4626 {
  function getDelegatorName() external view returns (string memory);

  function getDelegatorType() external view returns (string memory);

  function checkApproval(address user) external view returns (bool);

  function checkApproval(
    address user,
    uint256 allowance
  ) external view returns (bool);

  function initialDeposit(
    uint256 assets,
    address receiver
  ) external returns (uint256);

  function depositFee(uint256 amount) external view returns (uint256);

  function withdrawFee(uint256 amount) external view returns (uint256);
}

