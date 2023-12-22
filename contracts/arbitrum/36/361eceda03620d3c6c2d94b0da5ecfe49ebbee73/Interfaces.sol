// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;
import "./IERC20Upgradeable.sol";
import "./IVotesUpgradeable.sol";

interface IStaker {
  function stake(uint) external;
}

interface IArbDepositor {
  function depositFor(address _user, uint _amount) external;
}

interface IPlutusChef {
  function depositFor(address _user, uint128 _amount) external;
}

interface ITokenMinter {
  function mint(address, uint) external;

  function burn(address, uint) external;
}

interface IERC20VotesUpgradeable is IERC20Upgradeable, IVotesUpgradeable {}

interface ITokenDistributor {
  function claim() external;

  function claimableTokens(address _user) external view returns (uint _alloc);

  // returns block.number
  function claimPeriodStart() external view returns (uint);
}

