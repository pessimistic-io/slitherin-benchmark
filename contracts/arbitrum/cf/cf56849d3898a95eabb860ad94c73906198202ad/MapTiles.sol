//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./ICorruptionCryptsInternal.sol";

contract MapTiles is Initializable {
    event MapTilesInitialized(MapTile[] _mapTiles);

    mapping(uint8 => MapTile) mapTiles;

    function initMapTiles() internal {
        // See https://boardgamegeek.com/image/3128699/karuba
        // for the tile road directions

        MapTile[] memory _mapTiles = new MapTile[](36);

        _mapTiles[0] = MapTile({
            mapTileId: 1,
            mapTileType: 1,
            moves: 2,
            north: false,
            east: true,
            south: false,
            west: true
        });
        _mapTiles[1] = MapTile({
            mapTileId: 2,
            mapTileType: 2,
            moves: 2,
            north: false,
            east: true,
            south: false,
            west: true
        });
        _mapTiles[2] = MapTile({
            mapTileId: 3,
            mapTileType: 3,
            moves: 2,
            north: false,
            east: true,
            south: true,
            west: false
        });
        _mapTiles[3] = MapTile({
            mapTileId: 4,
            mapTileType: 4,
            moves: 2,
            north: false,
            east: false,
            south: true,
            west: true
        });
        _mapTiles[4] = MapTile({
            mapTileId: 5,
            mapTileType: 5,
            moves: 3,
            north: false,
            east: true,
            south: true,
            west: true
        });
        _mapTiles[5] = MapTile({
            mapTileId: 6,
            mapTileType: 6,
            moves: 3,
            north: false,
            east: true,
            south: true,
            west: true
        });

        _mapTiles[6] = MapTile({
            mapTileId: 7,
            mapTileType: 7,
            moves: 4,
            north: true,
            east: true,
            south: true,
            west: true
        });
        _mapTiles[7] = MapTile({
            mapTileId: 8,
            mapTileType: 8,
            moves: 4,
            north: true,
            east: true,
            south: true,
            west: true
        });
        _mapTiles[8] = MapTile({
            mapTileId: 9,
            mapTileType: 9,
            moves: 2,
            north: true,
            east: true,
            south: false,
            west: false
        });
        _mapTiles[9] = MapTile({
            mapTileId: 10,
            mapTileType: 10,
            moves: 2,
            north: true,
            east: false,
            south: false,
            west: true
        });
        _mapTiles[10] = MapTile({
            mapTileId: 11,
            mapTileType: 11,
            moves: 3,
            north: true,
            east: true,
            south: false,
            west: true
        });
        _mapTiles[11] = MapTile({
            mapTileId: 12,
            mapTileType: 12,
            moves: 3,
            north: true,
            east: true,
            south: false,
            west: true
        });

        _mapTiles[12] = MapTile({
            mapTileId: 13,
            mapTileType: 13,
            moves: 2,
            north: false,
            east: true,
            south: false,
            west: true
        });
        _mapTiles[13] = MapTile({
            mapTileId: 14,
            mapTileType: 14,
            moves: 2,
            north: false,
            east: true,
            south: false,
            west: true
        });
        _mapTiles[14] = MapTile({
            mapTileId: 15,
            mapTileType: 15,
            moves: 2,
            north: false,
            east: true,
            south: false,
            west: true
        });
        _mapTiles[15] = MapTile({
            mapTileId: 16,
            mapTileType: 16,
            moves: 2,
            north: false,
            east: true,
            south: false,
            west: true
        });
        _mapTiles[16] = MapTile({
            mapTileId: 17,
            mapTileType: 17,
            moves: 2,
            north: true,
            east: false,
            south: true,
            west: false
        });
        _mapTiles[17] = MapTile({
            mapTileId: 18,
            mapTileType: 18,
            moves: 2,
            north: true,
            east: false,
            south: true,
            west: false
        });

        _mapTiles[18] = MapTile({
            mapTileId: 19,
            mapTileType: 19,
            moves: 2,
            north: false,
            east: true,
            south: false,
            west: true
        });
        _mapTiles[19] = MapTile({
            mapTileId: 20,
            mapTileType: 20,
            moves: 2,
            north: false,
            east: true,
            south: false,
            west: true
        });
        _mapTiles[20] = MapTile({
            mapTileId: 21,
            mapTileType: 21,
            moves: 2,
            north: false,
            east: true,
            south: true,
            west: false
        });
        _mapTiles[21] = MapTile({
            mapTileId: 22,
            mapTileType: 22,
            moves: 2,
            north: false,
            east: false,
            south: true,
            west: true
        });
        _mapTiles[22] = MapTile({
            mapTileId: 23,
            mapTileType: 23,
            moves: 3,
            north: true,
            east: true,
            south: true,
            west: false
        });
        _mapTiles[23] = MapTile({
            mapTileId: 24,
            mapTileType: 24,
            moves: 3,
            north: true,
            east: false,
            south: true,
            west: true
        });

        _mapTiles[24] = MapTile({
            mapTileId: 25,
            mapTileType: 25,
            moves: 4,
            north: true,
            east: true,
            south: true,
            west: true
        });
        _mapTiles[25] = MapTile({
            mapTileId: 26,
            mapTileType: 26,
            moves: 4,
            north: true,
            east: true,
            south: true,
            west: true
        });
        _mapTiles[26] = MapTile({
            mapTileId: 27,
            mapTileType: 27,
            moves: 2,
            north: true,
            east: true,
            south: false,
            west: false
        });
        _mapTiles[27] = MapTile({
            mapTileId: 28,
            mapTileType: 28,
            moves: 2,
            north: true,
            east: false,
            south: false,
            west: true
        });
        _mapTiles[28] = MapTile({
            mapTileId: 29,
            mapTileType: 29,
            moves: 3,
            north: true,
            east: true,
            south: true,
            west: false
        });
        _mapTiles[29] = MapTile({
            mapTileId: 30,
            mapTileType: 30,
            moves: 3,
            north: true,
            east: false,
            south: true,
            west: true
        });

        _mapTiles[30] = MapTile({
            mapTileId: 31,
            mapTileType: 31,
            moves: 2,
            north: true,
            east: false,
            south: true,
            west: false
        });
        _mapTiles[31] = MapTile({
            mapTileId: 32,
            mapTileType: 32,
            moves: 2,
            north: true,
            east: false,
            south: true,
            west: false
        });
        _mapTiles[32] = MapTile({
            mapTileId: 33,
            mapTileType: 33,
            moves: 2,
            north: true,
            east: false,
            south: true,
            west: false
        });
        _mapTiles[33] = MapTile({
            mapTileId: 34,
            mapTileType: 34,
            moves: 2,
            north: true,
            east: false,
            south: true,
            west: false
        });
        _mapTiles[34] = MapTile({
            mapTileId: 35,
            mapTileType: 35,
            moves: 2,
            north: true,
            east: false,
            south: true,
            west: false
        });
        _mapTiles[35] = MapTile({
            mapTileId: 36,
            mapTileType: 36,
            moves: 2,
            north: true,
            east: false,
            south: true,
            west: false
        });

        for (uint8 i = 0; i < 36; i++) {
            mapTiles[i] = _mapTiles[i];
        }

        emit MapTilesInitialized(_mapTiles);
    }
}

