// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

abstract contract EIP712 {
  bytes32 private immutable DOMAIN_SEPARATOR;
  uint256 private immutable CHAIN_ID;
  address private immutable THIS;

  bytes32 private immutable NAME_HASH;
  bytes32 private immutable VERSION_HASH;
  bytes32 private immutable TYPE_HASH;

  constructor(string memory _name, string memory _version) {
    bytes32 nameHash = keccak256(bytes(_name));
    bytes32 versionHash = keccak256(bytes(_version));
    bytes32 typeHash = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    NAME_HASH = nameHash;
    VERSION_HASH = versionHash;
    CHAIN_ID = block.chainid;
    DOMAIN_SEPARATOR = buildDomainSeparator(typeHash, nameHash, versionHash);
    THIS = address(this);
    TYPE_HASH = typeHash;
  }

  function buildDomainSeparator(bytes32 _typeHash, bytes32 _nameHash, bytes32 _versionHash) private view returns (bytes32) {
     return keccak256(abi.encode(_typeHash, _nameHash, _versionHash, block.chainid, address(this)));
  }

  function _domainSeparator() internal view returns (bytes32) {
    if(address(this) == THIS && block.chainid == CHAIN_ID) {
      return DOMAIN_SEPARATOR;
    } else {
      return buildDomainSeparator(TYPE_HASH, NAME_HASH, VERSION_HASH);
    }
  }

  function _createMessageHash(bytes32 _structHash) internal view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), _structHash));
  }

  function domainSeparator() external view returns (bytes32) {
    return _domainSeparator();
  }
}
