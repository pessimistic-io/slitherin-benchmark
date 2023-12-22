// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
import "./ERC721.sol";
import "./ECDSA.sol";

contract AirdropByArb {
  using ECDSA for bytes32;
  ERC721 public immutable cat;
  address public immutable owner;
  address public constant from = 0x8fD892cd0Cc9C38bd28d637926F48ef7179f07FA;
  mapping(address => bool) public claimed;

  constructor(ERC721 _cat) {
    cat = _cat;
    owner = msg.sender;
  }

  function claim(uint256 time, uint16 tokenId, bytes calldata signatures) external {
    require(!claimed[msg.sender], 'already claimed');
    require(time > block.timestamp, 'too late');
    bytes32 hash = keccak256(abi.encodePacked(time, tokenId, msg.sender, address(this)));
    address signer = hash.toEthSignedMessageHash().recover(signatures);
    require(signer == owner, 'not owner');
    claimed[msg.sender] = true;
    cat.safeTransferFrom(from, msg.sender, tokenId);
  }
}

