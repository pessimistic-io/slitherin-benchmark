// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0 <0.8.0;

import "./Ownable.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {IPriceOracleGetter} from "./IPriceOracleGetter.sol";

contract FallbackOracle is IPriceOracleGetter, Ownable {
  event AssetSourceUpdated(address indexed asset, address indexed source);

  mapping(address => IPriceOracle) private assetsSources;

  /// @notice Gets an asset price by address
  /// @param asset The asset address
  function getAssetPrice(address asset) public view override returns (uint256) {
    IPriceOracle source = assetsSources[asset];
    return source.getAssetPrice();
  }

  /// @notice External function called by the governance to set or replace sources of assets
  /// @param assets The addresses of the assets
  /// @param sources The addresses of the sources of assets
  function setOracles(address[] memory assets, address[] memory sources) external onlyOwner {
    require(assets.length == sources.length, 'INCONSISTENT_PARAMS_LENGTH');
    for (uint256 i = 0; i < assets.length; i++) {
      assetsSources[assets[i]] = IPriceOracle(sources[i]);
      emit AssetSourceUpdated(assets[i], sources[i]);
    }
  }
}

