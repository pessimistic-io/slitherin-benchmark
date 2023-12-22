// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/******************************************************************************\
* Author: Nick Mudge <nick@perfectabstractions.com> (https://twitter.com/mudgen)
* EIP-2535 Diamonds: https://eips.ethereum.org/EIPS/eip-2535
/******************************************************************************/
import { IDiamondCut } from "./interfaces_IDiamondCut.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
// Remember to add the loupe functions from DiamondLoupeFacet to the diamond.
// The loupe functions are required by the EIP2535 Diamonds standard


library LibOracle {
    using SafeERC20 for IERC20;

    bytes32 constant ORACLE_STORAGE_POSITION = keccak256("oracle.portal.strateg.io");

    struct OracleEntry {
        bool enabled;
        uint8 decimals;
        uint256 price;
    }

    struct OracleStorage {
        mapping(address => bool) isUpdater;
        mapping(address => OracleEntry) entries;
    }

    function oracleStorage() internal pure returns (OracleStorage storage ds) {
        bytes32 position = ORACLE_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    function isUpdater(address _addr) internal view returns (bool) {
        return oracleStorage().isUpdater[_addr];
    }

    function setUpdater(bool _enabled, address _addr) internal returns (bool) {
        return oracleStorage().isUpdater[_addr] = _enabled;
    }

    function getRate(address _from, address _to, uint256 _amount) internal view returns (uint256) {

        OracleEntry storage from = oracleStorage().entries[_from];
        OracleEntry storage to = oracleStorage().entries[_to];

        require(from.enabled && to.enabled, "Asset oracle not enabled");

        uint256 fromBase = (_amount * from.price) /
            10 ** from.decimals;

        return fromBase * (10 ** to.decimals) / to.price;
    }

    function getPrice(address _from) internal view returns (uint256) {
        require(oracleStorage().entries[_from].enabled, "Price not enabled");
        return oracleStorage().entries[_from].price;
    }

    function setPrice(
        address _from, 
        uint256 _price
    ) internal {
        OracleStorage storage store = oracleStorage();
        store.entries[_from].price = _price;
    }

    function priceIsEnabled(
        address _asset
    ) internal view returns (bool) {
        OracleStorage storage store = oracleStorage();
        return store.entries[_asset].enabled;
    }

    function enablePrice(
        address _asset, 
        uint8 _decimals
    ) internal {
        OracleStorage storage store = oracleStorage();
        store.entries[_asset].enabled = true;
        store.entries[_asset].decimals = _decimals;
    }

    function disablePrice(
        address _asset
    ) internal {
        OracleStorage storage store = oracleStorage();
        store.entries[_asset].enabled = false;
        store.entries[_asset].decimals = 0;
    }
}

