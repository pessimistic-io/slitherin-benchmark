// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import { IERC20Upgradeable as IERC20 } from "./IERC20Upgradeable.sol";
import "./IVotesUpgradeable.sol";

import "./Errors.sol";
import "./IComposable.sol";

interface IDistributionERC20 is IVotesUpgradeable, IERC20, IComposable {
  event Distribution(uint256 indexed id, address indexed token, uint112 amount);
  event Claim(uint256 indexed id, address indexed person, uint112 amount);

  function claimed(uint256 id, address person) external view returns (bool);

  function distribute(address token, uint112 amount) external returns (uint256 id);
  function claim(uint256 id, address person) external;
}

error Delegation();
error FeeOnTransfer(address token);
error AlreadyClaimed(uint256 id, address person);

