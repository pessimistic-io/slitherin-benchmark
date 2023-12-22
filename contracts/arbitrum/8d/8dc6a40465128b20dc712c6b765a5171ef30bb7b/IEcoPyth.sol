// SPDX-License-Identifier: MIT
//   _   _ __  ____  __
//  | | | |  \/  \ \/ /
//  | |_| | |\/| |\  /
//  |  _  | |  | |/  \
//  |_| |_|_|  |_/_/\_\
//

pragma solidity 0.8.18;

import { PythStructs } from "./interfaces_IPyth.sol";

interface IEcoPyth {
  function getAssetIds() external view returns (bytes32[] memory);

  function getPriceUnsafe(bytes32 id) external view returns (PythStructs.Price memory price);

  function updatePriceFeeds(
    bytes32[] calldata _prices,
    bytes32[] calldata _publishTimeDiff,
    uint256 _minPublishTime,
    bytes32 _encodedVaas
  ) external;

  function buildPriceUpdateData(int24[] calldata _prices) external pure returns (bytes32[] memory _updateData);

  function buildPublishTimeUpdateData(
    uint24[] calldata _publishTimeDiff
  ) external pure returns (bytes32[] memory _updateData);

  function setUpdater(address _account, bool _isActive) external;

  function insertAssetId(bytes32 _assetId) external;

  function insertAssetIds(bytes32[] calldata _assetIds) external;
}

