// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./ERC721.sol";
import "./Strings.sol";
import "./Ownable.sol";

contract NftPerpWave is ERC721, Ownable {
  uint256 lastId;
  uint256 public startTimestamp;
  uint256 public endTimestamp;
  bytes32 public root;
  string baseURI;
  bool isResultsPublished;
  mapping(address => bool) claimed;

  constructor(
    bytes32 _root,
    string memory _name,
    string memory _symbol,
    string memory _baseURI,
    uint256 _startTimestamp,
    uint256 _endTimestamp
  ) ERC721(_name, _symbol) Ownable() {
    require(
      bytes(_baseURI).length > 0,
      "NftPerpWave::constructor: BaseURI needs to be initialized"
    );
    require(
      block.timestamp <= _startTimestamp && _startTimestamp < _endTimestamp,
      "NftPerpWave::constructor:Invalid time range for the campaign"
    );
    root = _root;
    baseURI = _baseURI;
    startTimestamp = _startTimestamp;
    endTimestamp = _endTimestamp;
  }

  ///@notice updates the root of the merkle tree
  ///@param _root new root
  function changeRoot(bytes32 _root) public onlyOwner {
    require(_root != root, "NftPerpWave::changeRoot: root can't be the same");
    root = _root;
  }

  ///@notice updates the baseURI of the contract
  ///@param _baseURI new baseURI
  ///@param _isResultsPublished true if the results are published
  function updateBaseURI(string memory _baseURI, bool _isResultsPublished) public onlyOwner {
    require(
      bytes(_baseURI).length > 0,
      "NftPerpWave::updateBaseURI: BaseURI needs to be initialized"
    );
    baseURI = _baseURI;
    isResultsPublished = _isResultsPublished;
  }

  ///@notice returns the URI for token with id tokenId
  ///@param tokenId id of the wanted token
  ///@return URI of the input token
  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    _requireMinted(tokenId);
    //fetch metadata file at basURI if results are not out yet, else fetch at baseURI/tokenID.json
    return
      isResultsPublished
        ? string(abi.encodePacked(baseURI, "/", Strings.toString(tokenId), ".json"))
        : baseURI;
  }

  ///@notice mints a participation NFT to the caller if the caller is approved (upon doing required tasks)
  ///@param proof proof of the inclusion in the merkle tree
  ///@param label label of msg.sender
  function claim(bytes32[] memory proof, string memory label) public {
    require(
      startTimestamp <= block.timestamp && block.timestamp <= endTimestamp,
      "NftPerpWave::claim:Campaign is not active"
    );
    require(!claimed[msg.sender], "NftPerpWave::claim:Already claimed");
    require(_verify(proof, label), "NftPerpWave::claim:Invalid proof");
    _safeMint(msg.sender, ++lastId);
    claimed[msg.sender] = true;
  }

  ///@notice executive minting function
  ///@param _to address of the receiver
  function executiveClaim(address _to) public onlyOwner {
    require(
      startTimestamp <= block.timestamp && block.timestamp <= endTimestamp,
      "NftPerpWave::claim:Campaign is not active"
    );
    require(!claimed[_to], "NftPerpWave::claim:Already claimed");
    _safeMint(_to, ++lastId);
    claimed[_to] = true;
  }

  ///@notice verifies the inclusion of msg.sende in the merkle tree if root != 0, else returns true
  ///@param proof proof of the inclusion in the merkle tree
  ///@param label label of msg.sender
  ///@return true if msg.sender is included in the tree with the label passed in input
  function _verify(bytes32[] memory proof, string memory label) internal view returns (bool) {
    if (root == 0x0) return true;
    bytes32 computedHash = keccak256(abi.encode(msg.sender, label));
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

