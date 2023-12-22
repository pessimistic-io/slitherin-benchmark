// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./ERC721URIStorage.sol";
import "./Ownable.sol";
import "./Counters.sol";

contract GOLToken is ERC721URIStorage, Ownable {
  using Counters for Counters.Counter;
  Counters.Counter private _tokenIds;
  uint price;
  mapping(uint => mapping(uint => uint)) minted;

  event Minted(uint id, address to, uint rows, uint initState);

  constructor() ERC721("GOLToken", "GOLT") payable {
    price = 0.001 ether;
  }

  function payToMint(uint rows, uint initState, string memory _tokenUri, bytes memory signature) payable public returns (uint) {
    require(msg.value >= price, "Please pay ETH to mint");
    require(rows >= 3 && rows <= 16, "Rows should be between 3 and 16");
    require(!initStateExists(rows, initState), "Init state already exists");

    bytes32 message = keccak256(
      abi.encodePacked(
        "\x19Ethereum Signed Message:\n32",
        keccak256(abi.encode(rows, initState, msg.sender))
      )
    );

    require(recoverSigner(message, signature) == owner(), "Signature not verified");

    _tokenIds.increment();
    uint newId = _tokenIds.current();
    minted[rows][initState] = newId;
    _safeMint(msg.sender, newId);
    _setTokenURI(newId, _tokenUri);

    payable(owner()).transfer(msg.value);

    emit Minted(newId, msg.sender, rows, initState);
    return newId;
  }

  function initStateExists(uint rows, uint initState) public view returns (bool) {
    return minted[rows][initState] != 0;
  }

  function setPrice(uint _price) onlyOwner() public {
    price = _price;
  }

  function getPrice() public view returns (uint) {
    return price;
  }

  function tokenIdOf(uint rows, uint initState) public view returns (uint) {
    return minted[rows][initState];
  }

  function splitSignature(bytes memory sig)
    internal
    pure
    returns (uint8 v, bytes32 r, bytes32 s)
  {
    require(sig.length == 65);

    assembly {
      r := mload(add(sig, 32)) // first 32 bytes, after the length prefix.
      s := mload(add(sig, 64)) // second 32 bytes.
      v := byte(0, mload(add(sig, 96))) // final byte (first byte of the next 32 bytes).
    }

    return (v, r, s);
  }

  function recoverSigner(bytes32 message, bytes memory sig)
    internal
    pure
    returns (address)
  {
    (uint8 v, bytes32 r, bytes32 s) = splitSignature(sig);

    return ecrecover(message, v, r, s);
  }
}

