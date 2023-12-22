library LegacyPills {
  uint256 constant _NF_BIT_MASK =
    0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  uint256 constant _TYPE_BIT_MASK =
    0x7fffffffffffffffffffffffffffffff00000000000000000000000000000000;
  uint256 constant _SUB_TYPE_BIT_MASK =
    0x00000000000000000000000000000000ffffffffffffffff0000000000000000;
  uint256 constant _ROOT_ID_BIT_MASK =
    0x000000000000000000000000000000000000000000000000ffffffffffffffff;

  function getTypeFromId(uint256 id) public pure returns (uint256) {
    return (id & _TYPE_BIT_MASK) >> 128;
  }

  function getSubTypeFromId(uint256 id) public pure returns (uint256) {
    return (id & _SUB_TYPE_BIT_MASK) >> 64;
  }

  function getRootIdFromId(uint256 id) public pure returns (uint256) {
    return (id & _ROOT_ID_BIT_MASK);
  }

  function removeNFBit(uint256 id) public pure returns (uint256) {
    return id & _NF_BIT_MASK;
  }
}

