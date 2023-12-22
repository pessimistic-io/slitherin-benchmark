//  SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IRewardRouterV2} from "./IRewardRouterV2.sol";
import {IRewardTracker} from "./IRewardTracker.sol";
import {IGlpManager} from "./IGlpManager.sol";
import {IGmxVault} from "./IGmxVault.sol";
import {SafeMath} from "./SafeMath.sol";
import {Addresses} from "./Addresses.sol";
import {IERC20Metadata as IERC20} from "./extensions_IERC20Metadata.sol";

library GLPHelper {
  using SafeMath for uint256;
  IGlpManager public constant glpManager = IGlpManager(Addresses.glpManager);
  IRewardTracker public constant stakedGlp = IRewardTracker(Addresses.stakedGlp);
  IRewardRouterV2 public constant glpRouter = IRewardRouterV2(Addresses.glpRouter);
  IERC20 public constant fsGLP = IERC20(Addresses.fsGLP);
  IGmxVault public constant glpVault = IGmxVault(Addresses.glpVault);

  function usdgAmounts(IERC20 token) public view returns (uint256) {
    return glpVault.usdgAmounts(address(token));
  }

  function getAumInUsdg() public view returns (uint256) {
    return glpManager.getAumInUsdg(true);
  }

  function glpPropCurrent(IERC20 token) public view returns (uint256) {
    return usdgAmounts(token).mul(1e18).div(getAumInUsdg());
  }

  function unstake(
    IERC20 receiveToken,
    uint amount,
    uint minOut
  ) internal returns (uint) {
    stakedGlp.approve(address(GLPHelper.glpRouter), amount);
    return glpRouter.unstakeAndRedeemGlp(
      address(receiveToken),
      amount,
      minOut,
      address(this)
    );
  }

  function wrapTransfer(
    IERC20 token,
    address receiver,
    uint amount
  ) internal returns (bool) {
    if(amount == 0) { return false; }
    else if (token == GLPHelper.fsGLP) {
      return IERC20(address(GLPHelper.stakedGlp)).transfer(receiver, amount);
    }
    return token.transfer(receiver, amount);
  }

  function wrapTransferFrom(
    IERC20 token,
    address spender,
    address receiver,
    uint amount
  ) internal returns (bool) {
    if(amount == 0) { return false; }
    else if (token == GLPHelper.fsGLP) {
      return IERC20(address(GLPHelper.stakedGlp)).transferFrom(spender, receiver, amount);
    }
    return token.transferFrom(spender, receiver, amount);
  }
  /*
   * @notice Mint and stake GLP
   * @param tokenIn Address of the token to mint with
   * @param amountIn Amount of the token to mint with
   * @param minUsdg Minimum usdg to receive during swap for mint
   * @param minGlp Minimum amount of GLP to receive
   */
  function mintAndStake(
    IERC20 tokenIn,
    uint256 amountIn,
    uint minUsdg,
    uint minGlp
  ) internal returns (uint) {
    tokenIn.approve(address(GLPHelper.glpManager), amountIn);
    return glpRouter.mintAndStakeGlp(
      address(tokenIn),
      amountIn,
      minUsdg,
      minGlp
    );
  }

  function approve(
    address spender,
    uint256 amount
  ) internal returns (bool) {
    return stakedGlp.approve(spender, amount);
  }
}

