// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IERC721.sol";
import "./IERC1155.sol";
import "./SafeERC20.sol";
import "./ITroveMarketplace.sol";

// import "@forge-std/src/console.sol";

enum MarketplaceType {
  TROVE,
  SEAPORT_V1
}

struct MarketplaceTypeData {
  bytes4 interfaceID;
  string name;
}

struct MarketplaceData {
  address[] paymentTokens;
}

error InvalidMarketplaceId();
error InvalidMarketplace();

library LibMarketplaces {
  using SafeERC20 for IERC20;
  
  bytes32 constant DIAMOND_STORAGE_POSITION =
    keccak256("diamond.standard.sweep.storage");

  struct MarketplacesStorage {
    mapping(address => MarketplaceData) marketplacesData;
  }

  function diamondStorage()
    internal
    pure
    returns (MarketplacesStorage storage ds)
  {
    bytes32 position = DIAMOND_STORAGE_POSITION;
    assembly {
      ds.slot := position
    }
  }

  function _addMarketplace(
    address _marketplace,
    address[] memory _paymentTokens
  ) internal {
    if (_marketplace == address(0)) revert InvalidMarketplace();

    diamondStorage().marketplacesData[_marketplace] = MarketplaceData(
      _paymentTokens
    );

    for (uint256 i = 0; i < _paymentTokens.length; i++) {
      if (_paymentTokens[i] != address(0)) {
        IERC20(_paymentTokens[i]).approve(_marketplace, type(uint256).max);
      }
    }
  }

  // function _setMarketplaceTypeId(
  //   address _marketplace,
  //   uint16 _marketplaceTypeId
  // ) internal {
  //   diamondStorage()
  //     .marketplacesData[_marketplace]
  //     .marketplaceTypeId = _marketplaceTypeId;
  // }

  function _addMarketplaceToken(address _marketplace, address _token) internal {
    diamondStorage().marketplacesData[_marketplace].paymentTokens.push(_token);
    IERC20(_token).approve(_marketplace, type(uint256).max);
  }

  function _getMarketplaceData(address _marketplace)
    internal
    view
    returns (MarketplaceData storage marketplaceData)
  {
    marketplaceData = diamondStorage().marketplacesData[_marketplace];
  }

  function _getMarketplacePaymentTokens(address _marketplace)
    internal
    view
    returns (address[] storage paymentTokens)
  {
    paymentTokens = diamondStorage()
      .marketplacesData[_marketplace]
      .paymentTokens;
  }
}

