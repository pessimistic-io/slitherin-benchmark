//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./Ownable.sol";

import "./ERC721Burnable.sol";
import "./IERC721Receiver.sol";

import "./console.sol";

contract Pledge1of1 is Ownable, IERC721Receiver {

  ERC721Burnable public pepes;

  // One of one token IDs
  uint[] public oneOfOnes;

  // Deposits are allowed only during pledge period
  bool public isPledgePeriod = true;

  // Have one-of-ones been distributed
  bool public hasDistributed = false;

  // Have one-of-ones been deposited
  bool public deposited;

  // Total floors pledged
  uint public totalPledged;

  // Mapping of pledged token ID to pledgor address
  mapping (uint => address) public pledged;

  // Mapping of pledged token index to pledgor address
  mapping (uint => address) public pledgedIndex;

  // Mapping of pledged token ID to whether it was burned
  mapping (uint => bool) public burned;

  event LogPledged(address pledgor, uint tokenId, uint index);
  event LogDistributed(uint randomNumber, address winner, uint tokenId);
  event LogBurn(uint tokenId);

  constructor(
    address _pepes
  ) {
    require(_pepes != address(0), "Invalid address");
    pepes = ERC721Burnable(_pepes);
  }

  // Deposit one of ones to this contract
  function depositOneOfOnes(uint[] memory tokenIds)
  public
  onlyOwner
  returns (bool) {
    require(!deposited, "Already deposited");
    require(tokenIds.length == 11, "Invalid indices size");
    for (uint i = 0; i < tokenIds.length; i++) {
      oneOfOnes.push(tokenIds[i]);
      pepes.safeTransferFrom(msg.sender, address(this), tokenIds[i]);
    }
    deposited = true;
    return true;
  }

  // Pledge to burn pepes
  function pledge(uint[] memory tokenIds) 
  public
  returns (bool) {
    require(isPledgePeriod, "Must be pledge period");
    for (uint i = 0; i < tokenIds.length; i++) {
      require(pledged[tokenIds[i]] == address(0), "Token ID was already pledged");
      pledged[tokenIds[i]] = msg.sender;
      pledgedIndex[++totalPledged] = msg.sender;
      pepes.safeTransferFrom(msg.sender, address(this), tokenIds[i]);
      emit LogPledged(msg.sender, tokenIds[i], totalPledged);
    }
    return true;
  }

  // End the pledge period
  function endPledgePeriod()
  public
  onlyOwner
  returns (bool) {
    require(deposited, "1-of-1s must be deposited");
    isPledgePeriod = false;
    return true;
  }

  // Picks winners using randomNumbers fed from vrf
  function pickWinners(uint[] memory randomNumbers)
  public
  onlyOwner
  returns (bool) {
    require(!isPledgePeriod, "Pledge period is ongoing");
    require(!hasDistributed, "Already distributed");
    require(randomNumbers.length == 11, "Invalid random numbers");
    for (uint i = 0; i < randomNumbers.length; i++) {
      require(randomNumbers[i] <= totalPledged, "Invalid random number");
      pepes.safeTransferFrom(address(this), pledgedIndex[randomNumbers[i]], oneOfOnes[i]);
      emit LogDistributed(randomNumbers[i], pledgedIndex[randomNumbers[i]], oneOfOnes[i]);
    }
    hasDistributed = true;
    return true;
  }

  // Burn floors
  function burnFloors(uint[] memory tokenIds)
  public
  onlyOwner
  returns (bool) {
    require(!isPledgePeriod, "Pledge period is ongoing");
    for (uint i = 0; i < tokenIds.length; i++) {
      burned[tokenIds[i]] = true;
      pepes.burn(tokenIds[i]);
      emit LogBurn(tokenIds[i]);
    }
    return true;
  }

  function onERC721Received(
      address operator,
      address from,
      uint256 tokenId,
      bytes calldata data
  ) public override returns (bytes4) {
    return IERC721Receiver.onERC721Received.selector;
  }

}

