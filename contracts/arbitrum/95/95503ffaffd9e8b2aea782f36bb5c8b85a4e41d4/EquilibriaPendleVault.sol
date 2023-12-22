// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./ERC4626.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./IERC20.sol";
import "./SafeMath.sol";
import "./IERC20Metadata.sol";

import "./IEqbZap.sol";
import "./IPendleRouter.sol";
import "./IPendleBooster.sol";
import "./BaseEquilibriaVault.sol";

contract EquilibriaPendleVault is BaseEquilibriaVault {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  constructor(
    IERC20Metadata asset_,
    string memory name_,
    string memory symbol_
  ) BaseEquilibriaVault(asset_, name_, symbol_) {
    _initializePid(4);
  }

  function totalUnstakedAssets() public view override returns (uint256) {
    // ideally, the asset() of this vault should be fsGLP
    // return pendle camelot LP.balanceOf(address(this));
    return IERC20(asset()).balanceOf(address(this));
  }
}

