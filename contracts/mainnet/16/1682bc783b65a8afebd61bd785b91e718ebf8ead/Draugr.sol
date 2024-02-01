// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./Ownable.sol";
import "./OperatorFilterer.sol";
import "./IERC721Receiver.sol";
import "./ERC721Burnable.sol";
import "./ERC721.sol";

contract Draugr is  ERC721, IERC721Receiver  , Ownable, OperatorFilterer {


  /* Add minting logic here */

  /* Add metadata logic here */
  ERC721Burnable immutable aerin;

  uint256 public tokenId;

  mapping(address => uint256) public burnedByAddress;

  error AerinTokensOnly();

  constructor(
    address aerin_,
    string memory name_,
    string memory symbol_
  ) ERC721(name_, symbol_) OperatorFilterer(address(0), false)  {
    aerin = ERC721Burnable(aerin_);
  }

  /**
   *
   * @dev totalSupply: Return supply without need to be enumerable:
   *
   */
  function totalSupply() external view returns (uint256) {
    return (tokenId);
  }

  /**
   *
   * @dev onERC721Received:
   *
   */
  function onERC721Received(
    address,
    address from_,
    uint256 tokenId_,
    bytes memory
  ) external override returns (bytes4) {
    // Check this is an Aerin!
    if (msg.sender != address(aerin)) {
      revert AerinTokensOnly();
    }

    // Burn the sent token:
    aerin.burn(tokenId_);

    // Increment the user's burn counter:
    burnedByAddress[from_]++;

    // If we have received a multiple of four mint a Draugr
    if ((burnedByAddress[from_] % 4) == 0) {
      // Send Draugr

      // Collection is 1 indexed (i.e. first token will be 1, not 0)
      tokenId++;

      _mint(from_, tokenId);
    }

    return this.onERC721Received.selector;
  }

  function transferFrom(address from, address to, uint256 tokenId)
  public

  override
  onlyAllowedOperator(from)
  {
    super.transferFrom(from, to, tokenId);
  }

  function safeTransferFrom(address from, address to, uint256 tokenId)
  public

  override
  onlyAllowedOperator(from)
  {
    super.safeTransferFrom(from, to, tokenId);
  }

  function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data)
  public

  override
  onlyAllowedOperator(from)
  {
    super.safeTransferFrom(from, to, tokenId, data);
  }
}

