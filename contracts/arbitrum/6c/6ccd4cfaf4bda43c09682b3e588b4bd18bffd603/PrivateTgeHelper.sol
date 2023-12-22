// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./IPlutusPrivateTGE.sol";
import "./IERC20.sol";

interface IPrivateTgeHelper {
  function ALLOCATION() external view returns (uint256);

  function PRIVATE_TGE_TOTAL_RAISE() external view returns (uint256);

  function VESTING_STARTED_AT() external view returns (uint256);

  function EPOCH() external view returns (uint256);

  function CLIFF() external view returns (uint256);

  function VESTING_PERIOD() external view returns (uint256);

  function PRIVATE_TGE() external view returns (IPlutusPrivateTGE);

  function calculateShare(address _user, uint256 _quantity) external view returns (uint256);

  function plsClaimable(address _user) external view returns (uint256);

  function claimStartAt() external pure returns (uint256);
}

contract PrivateTgeHelper is IPrivateTgeHelper {
  uint256 public constant ALLOCATION = 4_200_000 * 1e18;
  uint256 public constant PRIVATE_TGE_TOTAL_RAISE = 284524761916000171659;
  uint256 public constant VESTING_STARTED_AT = 1_651_687_161;
  uint256 public constant EPOCH = 2_628_000 seconds;
  uint256 public constant CLIFF = EPOCH * 3;
  uint256 public constant VESTING_PERIOD = EPOCH * 3;

  IPlutusPrivateTGE public constant PRIVATE_TGE = IPlutusPrivateTGE(0x35cD01AaA22Ccae7839dFabE8C6Db2f8e5A7B2E0);

  /** VIEWS */
  /// @dev Calculate _user's share of _quantity
  function calculateShare(address _user, uint256 _quantity) external view returns (uint256) {
    return (PRIVATE_TGE.deposit(_user) * _quantity) / PRIVATE_TGE_TOTAL_RAISE;
  }

  function plsClaimable(address _user) external view returns (uint256) {
    return (PRIVATE_TGE.deposit(_user) * ALLOCATION) / PRIVATE_TGE_TOTAL_RAISE;
  }

  function claimStartAt() external pure returns (uint256) {
    unchecked {
      return VESTING_STARTED_AT + CLIFF;
    }
  }
}

