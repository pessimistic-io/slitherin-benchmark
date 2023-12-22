pragma solidity >=0.8.19;

// todo: is this library used anywhere?
library Pack {
    function pack(uint128 a, uint32 b) internal pure returns (uint256) {
        return (a << 32) | b;
    }

    function unpack(uint256 value) internal view returns (uint128 a, uint32 b) {
        a = uint128(value >> 32);
        b = uint32(value - uint256(a << 32));
    }
}

