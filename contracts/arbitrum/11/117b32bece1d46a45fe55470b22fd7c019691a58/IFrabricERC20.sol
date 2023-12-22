// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

import "./IDistributionERC20.sol";
import "./IFrabricWhitelist.sol";
import "./IIntegratedLimitOrderDEX.sol";

interface IRemovalFee {
  function removalFee(address person) external view returns (uint8);
}

interface IFreeze {
  event Freeze(address indexed person, uint64 until);

  function frozenUntil(address person) external view returns (uint64);
  function frozen(address person) external returns (bool);

  function freeze(address person, uint64 until) external;
  function triggerFreeze(address person) external;
}

interface IFrabricERC20 is IDistributionERC20, IFrabricWhitelist, IRemovalFee, IFreeze, IIntegratedLimitOrderDEX {
  event Removal(address indexed person, uint256 balance);

  function auction() external view returns (address);

  function mint(address to, uint256 amount) external;
  function burn(uint256 amount) external;

  function remove(address participant, uint8 fee) external;
  function triggerRemoval(address person) external;

  function paused() external view returns (bool);
  function pause() external;
}

interface IFrabricERC20Initializable is IFrabricERC20 {
  function initialize(
    string memory name,
    string memory symbol,
    uint256 supply,
    address parent,
    address tradeToken,
    address auction
  ) external;
}

error SupplyExceedsInt112(uint256 supply, int112 max);
error Frozen(address person);
error NothingToRemove(address person);
// Not Paused due to an overlap with the event
error CurrentlyPaused();
error Locked(address person, uint256 balanceAfterTransfer, uint256 lockedBalance);

