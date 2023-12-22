// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Ownable.sol";
import "./ERC721.sol";
import "./IWaveFactory.sol";

contract WaveContract is Ownable, ERC721 {
  string baseURI;
  bytes32 public root;
  uint256 public startTimestamp;
  uint256 public endTimestamp;
  uint256 public lastId;
  bool public customMetadata;
  IWaveFactory factory;
  mapping(bytes32 => bool) claimed;
  mapping(uint256 => string) public idToReward;

  event Claimed(address indexed user, uint256 indexed id, string reward);

  modifier onlyKeeper() {
    require(
      msg.sender == factory.keeper(),
      "WaveContract::onlyKeeper:Only keeper can call this function"
    );
    _;
  }

  constructor(
    string memory _name,
    string memory _symbol,
    string memory _baseURI,
    bytes32 _root,
    uint256 _startTimestamp,
    uint256 _endTimestamp
  ) Ownable() ERC721(_name, _symbol) {
    require(
      _startTimestamp < _endTimestamp,
      "WaveFactory::constructor:startTimestamp must be less than endTimestamp"
    );
    baseURI = _baseURI;
    root = _root;
    startTimestamp = _startTimestamp;
    endTimestamp = _endTimestamp;
    factory = IWaveFactory(msg.sender);
  }

  function changeRoot(bytes32 _root) public onlyKeeper {
    root = _root;
  }

  function changeBaseURI(string memory _baseURI, bool _customMetadata) public onlyKeeper {
    baseURI = _baseURI;
    customMetadata = _customMetadata;
  }

  function changeTimings(uint256 _startTimestamp, uint256 _endTimestamp) public onlyOwner {
    require(
      _startTimestamp < _endTimestamp,
      "WaveFactory::changeTimings:startTimestamp must be less than endTimestamp"
    );
    startTimestamp = _startTimestamp;
    endTimestamp = _endTimestamp;
  }

  function claim(bytes32[] memory proof, string memory reward) public {
    require(
      startTimestamp <= block.timestamp && block.timestamp <= endTimestamp,
      "WaveContract::claim:Wave not active"
    );
    bytes32 leaf = keccak256(abi.encode(msg.sender, reward));
    require(!claimed[leaf], "WaveContract::claim:Already claimed");
    require(_verify(proof, leaf), "WaveContract::claim:Invalid proof");
    _safeMint(msg.sender, ++lastId);
    idToReward[lastId] = reward;
    claimed[leaf] = true;
    emit Claimed(msg.sender, lastId, reward);
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    _requireMinted(tokenId);
    return
      customMetadata
        ? string(abi.encodePacked(baseURI, "/", Strings.toString(tokenId), ".json"))
        : string(abi.encodePacked(baseURI, "/", idToReward[tokenId], ".json"));
  }

  function award(uint256[] memory winners, string memory reward) public onlyOwner {
    for (uint256 i = 0; i < winners.length; i++) {
      idToReward[winners[i]] = reward;
    }
  }

  ///@notice verifies the inclusion of leaf in the merkle tree if root != 0, else returns true
  ///@param proof proof of the inclusion in the merkle tree
  ///@param leaf to verify the inclusion of
  ///@return true if msg.sender is included in the tree with the label passed in input
  function _verify(bytes32[] memory proof, bytes32 leaf) private view returns (bool) {
    if (root == 0x0) return true;
    bytes32 computedHash = leaf;
    uint256 length = proof.length;
    for (uint256 i = 0; i < length; i++) {
      computedHash = _hashPair(computedHash, proof[i]);
    }
    // Check if the computed hash (root) is equal to the stored root
    return computedHash == root;
  }

  ///@notice sorts a pair of bytes32 and hashes it
  ///@param a first element to hash
  ///@param b second element to hash
  ///@return hash of the two inputs
  function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
    return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
  }

  ///@notice efficient hashing using assembly
  ///@param a first element to hash
  ///@param b second element to hash
  ///@return value of the hash of the inputs
  function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
    /// @solidity memory-safe-assembly
    assembly {
      mstore(0x00, a)
      mstore(0x20, b)
      value := keccak256(0x00, 0x40)
    }
  }
}

