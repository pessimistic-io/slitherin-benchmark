// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;
pragma abicoder v2;

import "./IERC20Extended.sol";
import "./ISynthetix.sol";
import "./ISynthAddressProxy.sol";
import "./IUniswapV2RouterSwapOnly.sol";
import "./IUniswapV2Router.sol";

library EasySwapperStructs {
  struct WithdrawProps {
    IUniswapV2RouterSwapOnly swapRouter;
    SynthetixProps synthetixProps;
    IERC20Extended weth;
    IERC20Extended nativeAssetWrapper;
  }

  struct SynthetixProps {
    ISynthetix snxProxy;
    IERC20Extended swapSUSDToAsset; // usdc or dai
    ISynthAddressProxy sUSDProxy;
  }
}

