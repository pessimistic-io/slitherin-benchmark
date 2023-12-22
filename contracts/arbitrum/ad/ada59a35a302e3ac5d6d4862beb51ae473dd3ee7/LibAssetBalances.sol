// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./SafeMath.sol";
import "./Strings.sol";
import "./AssetAmount.sol";
import "./LibAsset.sol";

using Strings for uint256;

library LibAssetBalances {
  uint8 constant MAX_ENTRIES = 10;

  struct AssetBalance {
    uint256 asset;
    uint256 balance;
  }

  struct AssetBalances {
    AssetBalance[MAX_ENTRIES] entries;
    uint8 end;
  }

  function getAssetBalance(AssetBalances memory entrySet, Asset memory asset) internal pure returns (uint256) {
    AssetBalance[MAX_ENTRIES] memory entries = entrySet.entries;
    uint256 assetAsInt = LibAsset.encodeAsset(asset);
    for (uint16 i = 0; i < entrySet.end; ++i) {
      if (entries[i].asset == assetAsInt) {
        return entries[i].balance;
      }
    }
    return 0;
  }

  function credit(
    AssetBalances memory entrySet,
    uint256 assetAsInt,
    uint256 amount
  ) internal pure {
    if (amount > 0) {
      uint256 index = getAssetIndex(entrySet, assetAsInt);
      (bool success, uint256 newBalance) = SafeMath.tryAdd(entrySet.entries[index].balance, amount);
      if (!success) {
        revertArithmetic('credit', assetAsInt, entrySet.entries[index].balance, amount);
      }
      updateBalance(entrySet, index, newBalance);
    }
  }

  function debit(
    AssetBalances memory entrySet,
    uint256 assetAsInt,
    uint256 amount
  ) internal pure {
    if (amount > 0) {
      uint256 index = getAssetIndex(entrySet, assetAsInt);
      (bool success, uint256 newBalance) = SafeMath.trySub(entrySet.entries[index].balance, amount);
      if (!success) {
        revertArithmetic('debit', assetAsInt, entrySet.entries[index].balance, amount);
      }
      updateBalance(entrySet, index, newBalance);
    }
  }

  function revertArithmetic(string memory op, uint256 assetAsInt, uint256 a, uint256 b) internal pure {
    Asset memory asset = LibAsset.decodeAsset(assetAsInt);       
    revert(string.concat(
      op,
      ' assetType=', 
      uint256(asset.assetType).toString(),
      ' assetAddress=', 
      uint256(uint160(asset.assetAddress)).toHexString(),
      ' values ',
      a.toString(), 
      ', ', 
      b.toString()));
  }

  function credit(
    AssetBalances memory entrySet,
    Asset memory asset,
    uint256 amount
  ) internal pure {
    credit(entrySet, LibAsset.encodeAsset(asset), amount);
  }

  function debit(
    AssetBalances memory entrySet,
    Asset memory asset,
    uint256 amount
  ) internal pure {
    debit(entrySet, LibAsset.encodeAsset(asset), amount);
  }

  function updateBalance(
    AssetBalances memory entrySet,
    uint256 index,
    uint256 newBalance
  ) internal pure returns (uint256) {
    if (newBalance == 0) {
      removeAt(entrySet, index);
    } else {
      entrySet.entries[index].balance = newBalance;
    }
    return newBalance;
  }

  function removeAt(AssetBalances memory entrySet, uint256 index) internal pure {
    entrySet.entries[index] = entrySet.entries[entrySet.end - 1];
    --entrySet.end;
  }

  function getAssetIndex(AssetBalances memory entrySet, Asset memory asset) internal pure returns (uint256) {
    uint256 assetAsInt = LibAsset.encodeAsset(asset);
    return getAssetIndex(entrySet, assetAsInt);
  }

  function getAssetIndex(AssetBalances memory entrySet, uint256 assetAsInt) internal pure returns (uint256) {
    for (uint256 i = 0; i < entrySet.end; ++i) {
      if (entrySet.entries[i].asset == assetAsInt) {
        return i;
      }
    }
    require(entrySet.end < MAX_ENTRIES, 'too many token balances');
    entrySet.entries[entrySet.end] = AssetBalance(assetAsInt, 0);
    return entrySet.end++;
  }

  function getAssetCount(AssetBalances memory entrySet) internal pure returns (uint8) {
    return entrySet.end;
  }

  function getAssetAt(AssetBalances memory entrySet, uint8 index) internal pure returns (AssetAmount memory) {
    require(index < entrySet.end, 'index out of bounds while accessing asset balances');
    Asset memory a = LibAsset.decodeAsset(entrySet.entries[index].asset);
    return AssetAmount(a, entrySet.entries[index].balance);
  }
}

