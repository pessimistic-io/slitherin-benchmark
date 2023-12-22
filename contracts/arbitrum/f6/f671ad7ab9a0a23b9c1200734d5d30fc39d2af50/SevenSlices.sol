// SPDX-License-Identifier: MIT
// Cowri Labs Inc.

pragma solidity =0.8.10;

contract SevenSlices {
    uint256 constant NUMBER_OF_SLICES = 7;
    uint256 constant NUMBER_OF_SLOPES = NUMBER_OF_SLICES - 1;
    int128 immutable m0;
    int128 immutable m1;
    int128 immutable m2;
    int128 immutable m3;
    int128 immutable m4;
    int128 immutable m5;
    int128 immutable k0;
    int128 immutable k1;
    int128 immutable k2;
    int128 immutable k3;
    int128 immutable k4;
    int128 immutable k5;
    int128 immutable k6;
    int128 immutable a0;
    int128 immutable a1;
    int128 immutable a2;
    int128 immutable a3;
    int128 immutable a4;
    int128 immutable a5;
    int128 immutable a6;
    int128 immutable b0;
    int128 immutable b1;
    int128 immutable b2;
    int128 immutable b3;
    int128 immutable b4;
    int128 immutable b5;
    int128 immutable b6;

    constructor(
        int128[] memory ms,
        int128[] memory _as,
        int128[] memory bs,
        int128[] memory ks
    ) {
        require(ms.length == NUMBER_OF_SLOPES);
        require(_as.length == NUMBER_OF_SLICES);
        require(bs.length == NUMBER_OF_SLICES);
        require(ks.length == NUMBER_OF_SLICES);
        m0 = ms[0];
        m1 = ms[1];
        m2 = ms[2];
        m3 = ms[3];
        m4 = ms[4];
        m5 = ms[5];
        k0 = ks[0];
        k1 = ks[1];
        k2 = ks[2];
        k3 = ks[3];
        k4 = ks[4];
        k5 = ks[5];
        k6 = ks[6];
        a0 = _as[0];
        a1 = _as[1];
        a2 = _as[2];
        a3 = _as[3];
        a4 = _as[4];
        a5 = _as[5];
        a6 = _as[6];
        b0 = bs[0];
        b1 = bs[1];
        b2 = bs[2];
        b3 = bs[3];
        b4 = bs[4];
        b5 = bs[5];
        b6 = bs[6];
    }

    function getSlopes() public view returns (int128[] memory slopes) {
        slopes = new int128[](NUMBER_OF_SLOPES);
        slopes[0] = m0;
        slopes[1] = m1;
        slopes[2] = m2;
        slopes[3] = m3;
        slopes[4] = m4;
        slopes[5] = m5;
    }

    function getAs() public view returns (int128[] memory _as) {
        _as = new int128[](NUMBER_OF_SLICES);
        _as[0] = a0;
        _as[1] = a1;
        _as[2] = a2;
        _as[3] = a3;
        _as[4] = a4;
        _as[5] = a5;
        _as[6] = a6;
    }

    function getBs() public view returns (int128[] memory bs) {
        bs = new int128[](NUMBER_OF_SLICES);
        bs[0] = b0;
        bs[1] = b1;
        bs[2] = b2;
        bs[3] = b3;
        bs[4] = b4;
        bs[5] = b5;
        bs[6] = b6;
    }

    function getKs() public view returns (int128[] memory ks) {
        ks = new int128[](NUMBER_OF_SLICES);
        ks[0] = k0;
        ks[1] = k1;
        ks[2] = k2;
        ks[3] = k3;
        ks[4] = k4;
        ks[5] = k5;
        ks[6] = k6;
    }
}

