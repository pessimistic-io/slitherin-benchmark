// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./Ownable.sol";
import "./ERC721.sol";
import "./ERC2771Context.sol";
import "./IWaveFactory.sol";

contract WaveContract is ERC2771Context, Ownable, ERC721 {
  string baseURI;
  bytes32 public root;
  uint256 public startTimestamp;
  uint256 public endTimestamp;
  uint256 public lastId;
  bool public customMetadata;
  IWaveFactory factory;
  mapping(bytes32 => bool) claimed;
  mapping(uint256 => string) public idToReward;

  struct AirdropParams {
    string reward;
    address user;
  }

  event Claimed(address indexed user, uint256 indexed id, string reward);

  modifier onlyKeeper() {
    require(
      _msgSender() == factory.keeper(),
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
    uint256 _endTimestamp,
    address _trustedForwarder
  ) ERC2771Context(_trustedForwarder) Ownable() ERC721(_name, _symbol) {
    require(
      _startTimestamp < _endTimestamp,
      "WaveFactory::constructor:startTimestamp must be less than endTimestamp"
    );
    baseURI = _baseURI;
    root = _root;
    startTimestamp = _startTimestamp;
    endTimestamp = _endTimestamp;
    factory = IWaveFactory(_msgSender());
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
    bytes32 leaf = keccak256(abi.encode(_msgSender(), reward));
    require(!claimed[leaf], "WaveContract::claim:Already claimed");
    require(_verify(proof, leaf), "WaveContract::claim:Invalid proof");
    _safeMint(_msgSender(), ++lastId);
    idToReward[lastId] = reward;
    claimed[leaf] = true;
    emit Claimed(_msgSender(), lastId, reward);
  }

  function airdrop(AirdropParams[] memory params) public onlyOwner {
    for (uint256 i = 0; i < params.length; i++) {
      _safeMint(params[i].user, ++lastId);
      idToReward[lastId] = params[i].reward;
      claimed[keccak256(abi.encode(params[i].user, params[i].reward))] = true;
      emit Claimed(params[i].user, lastId, params[i].reward);
    }
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    _requireMinted(tokenId);
    return
      customMetadata
        ? string(abi.encodePacked(baseURI, "/", Strings.toString(tokenId), ".json"))
        : string(abi.encodePacked(baseURI, "/", idToReward[tokenId], ".json"));
  }

  function award(uint256[] memory winnerIds, string memory reward) public onlyOwner {
    for (uint256 i = 0; i < winnerIds.length; i++) {
      idToReward[winnerIds[i]] = reward;
    }
  }

  ///@notice verifies the inclusion of leaf in the merkle tree if root != 0, else returns true
  ///@param proof proof of the inclusion in the merkle tree
  ///@param leaf to verify the inclusion of
  ///@return true if _msgSender() is included in the tree with the label passed in input
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

  ///@dev use ERC2771Context to get sender and data
  function _msgData() internal view override(ERC2771Context, Context) returns (bytes calldata) {
    return ERC2771Context._msgData();
  }

  function _msgSender() internal view override(ERC2771Context, Context) returns (address) {
    return ERC2771Context._msgSender();
  }
}

