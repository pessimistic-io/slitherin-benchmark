// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

import "./ERC20_IERC20Upgradeable.sol";
import "./ERC721_IERC721Upgradeable.sol";

import {Context} from "./Context.sol";
import "./Routing.sol";

import {CapitalAssetType} from "./ICapitalLedger.sol";
import {IPoolTokens} from "./IPoolTokens.sol";

import {ITranchedPool} from "./ITranchedPool.sol";

using Routing.Context for Context;

library PoolTokensAsset {
  CapitalAssetType public constant AssetType = CapitalAssetType.ERC721;

  /**
   * @notice Get the type of asset that this contract adapts.
   * @return the asset type
   */
  function isType(Context context, address assetAddress) internal view returns (bool) {
    return assetAddress == address(context.poolTokens());
  }

  /**
   * @notice Get whether or not the given asset is valid
   * @return true - all pool tokens are valid
   */
  function isValid(Context, uint256) internal pure returns (bool) {
    return true;
  }

  /**
   * @notice Get the point-in-time USDC equivalent value of the Pool Token asset. This
   *  specifically attempts to return the "principle" or "at-risk" USDC value of
   *  the asset and does not include rewards, interest, or other benefits.
   * @param context goldfinch context for routing
   * @param assetTokenId tokenId of the Pool Token to evaluate
   * @return USDC equivalent value
   */
  function getUsdcEquivalent(Context context, uint256 assetTokenId) internal view returns (uint256) {
    IPoolTokens.TokenInfo memory tokenInfo = context.poolTokens().getTokenInfo(assetTokenId);
    return tokenInfo.principalAmount - tokenInfo.principalRedeemed;
  }
}

