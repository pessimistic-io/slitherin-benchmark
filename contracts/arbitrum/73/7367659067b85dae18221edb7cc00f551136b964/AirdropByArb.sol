// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
import "./ERC721.sol";
import "./ECDSA.sol";
import "./ERC20.sol";

contract AirdropByArb {
  using ECDSA for bytes32;
  ERC721 public immutable cat;
  address public immutable owner;
  ERC20 public immutable rice;
  address public constant from = 0x8fD892cd0Cc9C38bd28d637926F48ef7179f07FA;
  uint16 public received;
  mapping(address => bool) public claimed;

  constructor(ERC721 _cat, ERC20 _rice) {
    cat = _cat;
    rice = _rice;
    owner = msg.sender;
  }

  function claim(address inv, uint256 amount, uint256 time, uint16 tokenId, bytes calldata signatures) external {
    require(!claimed[msg.sender], 'already claimed');
    require(time > block.timestamp, 'too late');
    bytes32 hash = keccak256(abi.encodePacked(time, tokenId, amount, msg.sender, address(this)));
    address signer = hash.toEthSignedMessageHash().recover(signatures);
    require(signer == owner, 'not owner');
    claimed[msg.sender] = true;
    received++;
    cat.safeTransferFrom(from, msg.sender, tokenId);
    rice.transferFrom(from, msg.sender, amount);
    if (inv != address(0) && inv != msg.sender) {
      rice.transferFrom(from, inv, amount);
    }
  }
}

