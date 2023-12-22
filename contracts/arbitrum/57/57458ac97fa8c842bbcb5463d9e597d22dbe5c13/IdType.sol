// SPDX-License-Identifier: Business Source License 1.1
pragma solidity ^0.8.19;

type IdType is uint64;

uint constant MAX_TOKEN_INDEX = type(uint64).max - 1;
IdType constant EMPTY_ID = IdType.wrap(type(uint64).min);
IdType constant FIRST_ID = IdType.wrap(type(uint64).min + 1);

library IdTypeLib {
    function toId(uint tokenId) internal pure returns (IdType) {
        require(tokenId <= MAX_TOKEN_INDEX, "Too big token ID");
        return IdType.wrap(uint64(tokenId));
    }

    function toTokenId(IdType id) internal pure returns (uint) {
        return IdType.unwrap(id);
    }

    function next(IdType id, uint offset) internal pure returns (IdType) {
        if (offset == 0) {
            return id;
        }
        return toId(IdType.unwrap(id) + offset);
    }

    function isEmpty(IdType id) internal pure returns (bool) {
        return IdType.unwrap(id) == 0;
    }

    function unwrap(IdType id) internal pure returns (uint64) {
        return IdType.unwrap(id);
    }
}

function idTypeEquals(IdType a, IdType b) pure returns (bool) {
    return IdType.unwrap(a) == IdType.unwrap(b);
}

function idTypeNotEquals(IdType a, IdType b) pure returns (bool) {
    return IdType.unwrap(a) != IdType.unwrap(b);
}

using {
      idTypeEquals as ==
    , idTypeNotEquals as !=
} for IdType global;

