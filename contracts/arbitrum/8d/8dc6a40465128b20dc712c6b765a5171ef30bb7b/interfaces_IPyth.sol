// SPDX-License-Identifier: MIT
//   _   _ __  ____  __
//  | | | |  \/  \ \/ /
//  | |_| | |\/| |\  /
//  |  _  | |  | |/  \
//  |_| |_|_|  |_/_/\_\
//

pragma solidity 0.8.18;

interface IPyth {
  function wormhole() external view returns (address);

  function isValidDataSource(uint16 dataSourceChainId, bytes32 dataSourceEmitterAddress) external view returns (bool);
}

// @notice avoid slither compilation bug by declaring struct outside of interface scope
struct IPythPriceInfo {
  // slot 1
  uint64 publishTime;
  int32 expo;
  int64 price;
  uint64 conf;
  // slot 2
  int64 emaPrice;
  uint64 emaConf;
}

// @notice avoid slither compilation bug by declaring struct outside of interface scope
struct IEcoPythPriceInfo {
  uint48 publishTime;
  int64 price;
}

// @notice avoid slither compilation bug by declaring struct outside of interface scope
struct IPythDataSource {
  uint16 chainId;
  bytes32 emitterAddress;
}

