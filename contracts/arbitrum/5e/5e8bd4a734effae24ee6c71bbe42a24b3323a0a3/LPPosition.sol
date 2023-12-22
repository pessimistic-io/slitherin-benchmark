// SPDX-License-Identifier: None
pragma solidity ^0.8.18;

import {EnumerableSet} from "./EnumerableSet.sol";
import {VanillaOptionPool} from "./VanillaOptionPool.sol";

library LPPosition {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    struct Key {
        address owner;
        uint256 expiry;
        uint256 strike;
        bool isCall;
        int24 tickLower;
        int24 tickUpper;
    }

    struct Info {
        uint128 liquidity;
        uint256 deposit_amount0;
        uint256 deposit_amount1;
    }

    struct PositionTicks {
        int24 tickLower;
        int24 tickUpper;
    }

    function hashPositionKey(
        LPPosition.Key memory key
    ) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    key.owner,
                    key.expiry,
                    key.strike,
                    key.isCall,
                    key.tickLower,
                    key.tickUpper
                )
            );
    }

    // @dev this function returns the hash which is used to find the LP position in mapping
    function get(
        mapping(bytes32 => LPPosition.Info) storage self,
        LPPosition.Key memory key
    ) internal view returns (LPPosition.Info storage lpPosition) {
        lpPosition = self[hashPositionKey(key)];
    }

    function create(
        mapping(bytes32 => LPPosition.Info) storage self,
        LPPosition.Key memory key,
        uint128 liquidity,
        uint256 deposit_amount0,
        uint256 deposit_amount1
    ) internal {
        self[hashPositionKey(key)] = LPPosition.Info({
            liquidity: liquidity,
            deposit_amount0: deposit_amount0,
            deposit_amount1: deposit_amount1
        });
    }

    function clear(
        mapping(bytes32 => LPPosition.Info) storage self,
        LPPosition.Key memory key
    ) internal {
        delete self[hashPositionKey(key)];
    }

    // methods for bytes32 set functionality

    function get(
        mapping(address => mapping(bytes32 => EnumerableSet.Bytes32Set))
            storage self,
        address owner,
        VanillaOptionPool.Key memory optionPoolKey
    )
        internal
        view
        returns (EnumerableSet.Bytes32Set storage lpPositionsBytes32Set)
    {
        return self[owner][VanillaOptionPool.hashOptionPool(optionPoolKey)];
    }

    function getValues(
        mapping(address => mapping(bytes32 => EnumerableSet.Bytes32Set))
            storage self,
        address owner,
        VanillaOptionPool.Key memory optionPoolKey
    ) internal view returns (bytes32[] memory) {
        return
            self[owner][VanillaOptionPool.hashOptionPool(optionPoolKey)]
                .values();
    }

    function addPos(
        mapping(address => mapping(bytes32 => EnumerableSet.Bytes32Set))
            storage self,
        LPPosition.Key memory lpPositionKey
    ) internal {
        bytes32 lpPositionHash = LPPosition.hashPositionKey(lpPositionKey);

        self[lpPositionKey.owner][
            VanillaOptionPool.hashOptionPool(
                VanillaOptionPool.Key({
                    expiry: lpPositionKey.expiry,
                    strike: lpPositionKey.strike,
                    isCall: lpPositionKey.isCall
                })
            )
        ].add(lpPositionHash);
    }

    function removePos(
        mapping(address => mapping(bytes32 => EnumerableSet.Bytes32Set))
            storage self,
        LPPosition.Key memory lpPositionKey
    ) internal {
        bytes32 lpPositionHash = LPPosition.hashPositionKey(lpPositionKey);
        self[lpPositionKey.owner][
            VanillaOptionPool.hashOptionPool(
                VanillaOptionPool.Key({
                    expiry: lpPositionKey.expiry,
                    strike: lpPositionKey.strike,
                    isCall: lpPositionKey.isCall
                })
            )
        ].remove(lpPositionHash);
    }

    // lp position ticks infos
    function updateTicksInfos(
        mapping(bytes32 lpPositionHash => PositionTicks)
            storage lpPositionsTicksInfos,
        LPPosition.Key memory lpPositionKey
    ) internal {
        bytes32 lpPositionHash = LPPosition.hashPositionKey(lpPositionKey);
        lpPositionsTicksInfos[lpPositionHash] = PositionTicks({
            tickLower: lpPositionKey.tickLower,
            tickUpper: lpPositionKey.tickUpper
        });
    }

    function clearTicksInfos(
        mapping(bytes32 lpPositionHash => PositionTicks)
            storage lpPositionsTicksInfos,
        LPPosition.Key memory lpPositionKey
    ) internal {
        bytes32 lpPositionHash = LPPosition.hashPositionKey(lpPositionKey);
        // clear
        delete lpPositionsTicksInfos[lpPositionHash];
    }
}

