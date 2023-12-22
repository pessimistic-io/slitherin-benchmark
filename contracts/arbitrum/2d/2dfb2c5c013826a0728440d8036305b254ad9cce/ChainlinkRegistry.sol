// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.7 <0.9.0;

import "./IChainlinkRegistry.sol";
import "./Governable.sol";
import "./CollectableDust.sol";

contract ChainlinkRegistry is Governable, CollectableDust, IChainlinkRegistry {
  mapping(address => mapping(address => address)) internal _feeds;

  constructor(address _governor) Governable(_governor) {}

  /// @inheritdoc IChainlinkRegistry
  function getFeedProxy(address _base, address _quote) public view returns (AggregatorV2V3Interface) {
    address _feed = _feeds[_base][_quote];
    if (_feed == address(0)) revert FeedNotFound();
    return AggregatorV2V3Interface(_feed);
  }

  /// @inheritdoc IFeedRegistry
  function decimals(address _base, address _quote) external view returns (uint8) {
    return getFeedProxy(_base, _quote).decimals();
  }

  /// @inheritdoc IFeedRegistry
  function description(address _base, address _quote) external view returns (string memory) {
    return getFeedProxy(_base, _quote).description();
  }

  /// @inheritdoc IFeedRegistry
  function version(address _base, address _quote) external view returns (uint256) {
    return getFeedProxy(_base, _quote).version();
  }

  /// @inheritdoc IFeedRegistry
  function latestRoundData(address _base, address _quote)
    external
    view
    returns (
      uint80,
      int256,
      uint256,
      uint256,
      uint80
    )
  {
    return getFeedProxy(_base, _quote).latestRoundData();
  }

  /// @inheritdoc IChainlinkRegistry
  function setFeedProxies(Feed[] calldata _proxies) external onlyGovernor {
    for (uint256 i; i < _proxies.length; i++) {
      if (address(_proxies[i].base) == address(0) || address(_proxies[i].quote) == address(0)) revert ZeroAddress();
      _feeds[_proxies[i].base][_proxies[i].quote] = _proxies[i].feed;
    }
    emit FeedsModified(_proxies);
  }

  function sendDust(
    address _to,
    address _token,
    uint256 _amount
  ) external onlyGovernor {
    _sendDust(_to, _token, _amount);
  }
}

