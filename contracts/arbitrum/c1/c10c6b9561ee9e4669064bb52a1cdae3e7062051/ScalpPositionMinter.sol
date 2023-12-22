//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Contracts
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {ERC721} from "./ERC721.sol";
import {ERC721Enumerable} from "./ERC721Enumerable.sol";
import {ERC721Burnable} from "./ERC721Burnable.sol";
import {Ownable} from "./Ownable.sol";
import {Counters} from "./Counters.sol";

contract ScalpPositionMinter is 
  ReentrancyGuard,
  ERC721('OP-ScalpPosition', 'OPSP'),
  ERC721Enumerable,
  ERC721Burnable,
  Ownable {

  using Counters for Counters.Counter;

  /// @dev Token ID counter for straddle positions
  Counters.Counter private _tokenIdCounter;

  address public optionScalpContract;

  constructor() {
    optionScalpContract = msg.sender;
    _tokenIdCounter.increment();
  }

  function setScalpContract(address _optionScalpContract)
  public
  onlyOwner {
    optionScalpContract = _optionScalpContract;
  }

  function mint(address to) public returns (uint tokenId) {
    require(
      msg.sender == optionScalpContract, 
      "Only option scalp contract can mint an option scalp position token"
    );
    tokenId = _tokenIdCounter.current();
    _tokenIdCounter.increment();
    _safeMint(to, tokenId);
    return tokenId;
  }

  function burn(uint256 id) public override {
    require(
      msg.sender == optionScalpContract,
      "Only option scalp contract can mint an option scalp position token"
    );
    _burn(id);
  }

  // The following functions are overrides required by Solidity.
  function _beforeTokenTransfer(
      address from,
      address to,
      uint256 tokenId,
      uint256 batchSize
  ) internal override(ERC721, ERC721Enumerable) {
      super._beforeTokenTransfer(from, to, tokenId, batchSize);
  }

  function supportsInterface(bytes4 interfaceId)
      public
      view
      override(ERC721, ERC721Enumerable)
      returns (bool)
  {
      return super.supportsInterface(interfaceId);
  }

  function totalSupply()
    public
    view
    override
    returns (uint256) {
      return _tokenIdCounter._value - 1; // Token id starts from 1
  }
}
