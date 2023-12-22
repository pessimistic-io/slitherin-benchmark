//  SPDX-License-Identifier: MIT
pragma solidity >=0.8.10;

import {HandledImpl} from "./HandledImpl.sol";
import {IRewardRouterV2} from "./IRewardRouterV2.sol";
import {EIP20Interface} from "./EIP20Interface.sol";

contract CErc20Compounded is HandledImpl {
  event FeeReceiver(address indexed oldReceiver, address indexed newReceiver);
  address public feeReceiver;
  address public mintRouter;

  function _setMintRouter (address newRouter) external {
    require(msg.sender == admin, "CErc20: Only admin");
    mintRouter = newRouter;
  }

  function getFeeReceiver() public view returns (address) {
    return (feeReceiver != address(0)) ? feeReceiver : admin;
  }

  function _setFeeReceiver (address newReceiver) external {
    require(msg.sender == admin, "CErc20: Only admin");
    address oldReceiver = getFeeReceiver();
    feeReceiver = newReceiver;
    emit FeeReceiver(oldReceiver, newReceiver);
  }

  function compoundFresh() internal override {
    if (totalSupply == 0 || !isGLP) { return; }
    /* Remember the initial block number */
    uint256 currentBlockNumber = getBlockNumber();
    uint256 accrualBlockNumberPrior = accrualBlockNumber;
    uint256 _glpBlockDelta = sub_(currentBlockNumber, accrualBlockNumberPrior);

    if (_glpBlockDelta < autoCompoundBlockThreshold) { return; }

    glpBlockDelta = _glpBlockDelta;
    prevExchangeRate = exchangeRateStoredInternal();

    // There is a new GLP Reward Router just for minting and burning GLP.
    /// https://medium.com/@gmx.io/gmx-deployment-updates-nov-2022-16572314874d
    address _mintRouter = (mintRouter != address(0))
      ? mintRouter
      : 0xB95DB5B167D75e6d04227CfFFA61069348d271F5;

    IRewardRouterV2 newRewardRouter = IRewardRouterV2(_mintRouter);

    IRewardRouterV2(glpRewardRouter).handleRewards(false, false, true, true, false, true, false);
    uint256 ethBalance = EIP20Interface(WETH).balanceOf(address(this));

    // if this is a GLP cToken, claim the ETH and esGMX rewards and stake the esGMX Rewards
    address _feeReceiver = getFeeReceiver();

    if (ethBalance > 0) {
      uint256 ethperformanceFee = div_(mul_(ethBalance, performanceFee), 10000);
      uint256 ethToCompound = sub_(ethBalance, ethperformanceFee);
      EIP20Interface(WETH).transfer(_feeReceiver, ethperformanceFee);
      newRewardRouter.mintAndStakeGlp(WETH, ethToCompound, 0, 0);
    }

    accrualBlockNumber = currentBlockNumber;
  }
}

