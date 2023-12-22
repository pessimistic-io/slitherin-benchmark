// SPDX-License-Identifier: MIT
pragma solidity ^0.8.14;

import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { IERC721 } from "./IERC721.sol";
import { IERC1155 } from "./IERC1155.sol";

import { LibSweep, PaymentTokenNotGiven } from "./LibSweep.sol";
import { LibMarketplaces, MarketplaceData, MarketplaceType } from "./LibMarketplaces.sol";

import { WithOwnership } from "./LibOwnership.sol";

contract MarketplacesFacet is WithOwnership {
  using SafeERC20 for IERC20;

  function TROVE_ID() external pure returns (MarketplaceType) {
    return MarketplaceType.TROVE;
  }

  function SEAPORT_V1_ID() external pure returns (MarketplaceType) {
    return MarketplaceType.SEAPORT_V1;
  }

  function addMarketplace(address _marketplace, address[] memory _paymentTokens)
    external
    onlyOwner
  {
    LibMarketplaces._addMarketplace(_marketplace, _paymentTokens);
  }

  // function setMarketplaceTypeId(address _marketplace, uint16 _marketplaceTypeId)
  //   external
  //   onlyOwner
  // {
  //   LibMarketplaces._setMarketplaceTypeId(_marketplace, _marketplaceTypeId);
  // }

  function addMarketplaceToken(address _marketplace, address _paymentToken)
    external
    onlyOwner
  {
    LibMarketplaces._addMarketplaceToken(_marketplace, _paymentToken);
  }

  function getMarketplaceData(address _marketplace)
    external
    view
    returns (MarketplaceData memory)
  {
    return LibMarketplaces._getMarketplaceData(_marketplace);
  }

  function getMarketplacePaymentTokens(address _marketplace)
    external
    view
    returns (address[] memory)
  {
    return LibMarketplaces._getMarketplacePaymentTokens(_marketplace);
  }
}

