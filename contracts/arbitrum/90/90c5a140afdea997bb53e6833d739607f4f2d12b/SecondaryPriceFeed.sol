// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./ISupraSValueFeed.sol";
import "./AccessControlEnumerable.sol";

contract SecondaryPriceFeed is AccessControlEnumerable {
  ISupraSValueFeed public sValueFeed;
  address owner;
  uint8 freshness = 60;

  mapping(uint64 => uint256) public prices;

  bytes32 public constant CONTROLLER = keccak256("CONTROLLER");

  constructor(address _sVauleFeed, address _admin) {
    sValueFeed = ISupraSValueFeed(_sVauleFeed);
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(CONTROLLER, _admin);
  }

  modifier validateData(uint64 _pairIndex) {
    ISupraSValueFeed.dataWithoutHcc memory data = sValueFeed.getSvalue(_pairIndex);
    
    prices[_pairIndex] = (data.price * 1e8) / (10 ** data.decimals); // scaled price
    uint256 publishTs = data.round / 1000;

    require(publishTs + freshness >= block.timestamp, "Price is stale");
    _;
  }

  function updateSValueFeed(address _sVauleFeed) public onlyRole(CONTROLLER) {
    sValueFeed = ISupraSValueFeed(_sVauleFeed);
  }

  function updateFreshness(uint8 _freshness) public onlyRole(CONTROLLER) {
    freshness = _freshness;
  }

  function getPrice(uint64 _pairIndex) external validateData(_pairIndex) returns (uint256 price) {
    return prices[_pairIndex];
  }
}

