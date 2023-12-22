//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./console.sol";

import {Ownable} from "./Ownable.sol";

import "./SafeERC20.sol";
import "./ERC20.sol";

import "./ERC721PresetMinterPauserAutoId.sol";
import "./IERC721Receiver.sol";

contract Gen2Pledge is Ownable, IERC721Receiver {

  struct Pledge {
    uint[] pepes;
    address pledgor;
  }

  // Diamond pepes address
  ERC721PresetMinterPauserAutoId public pepes;

  // Total pledged pepes
  uint public totalPledged;

  // Total pledges
  uint public pledgeIndex;

  // Target vote in %
  uint public targetVote;

  // % precision
  uint public percentPrecision = 10 ** 4;

  // Target hit
  bool public targetHit;

  // Mapping of pledged token ID to pledgor address
  mapping (uint => address) public pledged;

  // Mapping of pledges by index
  mapping (uint => Pledge) public pledgeByIndex;

  // Mapping of pledged token ID to whether it was burned
  mapping (uint => bool) public burned;

  event LogPledgedPepe(address pledgor, uint tokenId, uint index);
  event LogNewPledge(address pledgor, uint[] tokenIds, uint index);
  event LogBurn(uint tokenId);

  constructor(
    address _pepes,
    uint _targetVote
  ) {
    require(_pepes != address(0), "Invalid address");
    require(_targetVote != 0, "Invalid target vote");
    pepes = ERC721PresetMinterPauserAutoId(_pepes);
    targetVote = _targetVote;
  }

  // Pledge to burn pepes & vote for gen-2 mint
  function pledge(uint[][] memory tokenIds) 
  public
  returns (bool) {
    require(!targetHit, "Pledge target already hit");
    for (uint i = 0; i < tokenIds.length; i++) {
      if (!targetHit) {
        require(tokenIds[i].length > 0 && tokenIds[i].length <= 4, "Invalid token IDs length");
        for (uint j = 0; j < tokenIds[i].length; j++) {
          require(pledged[tokenIds[i][j]] == address(0), "Token ID was already pledged");
          pledged[tokenIds[i][j]] = msg.sender;
          pepes.safeTransferFrom(msg.sender, address(this), tokenIds[i][j]);
          totalPledged++;
          emit LogPledgedPepe(msg.sender, tokenIds[i][j], ++pledgeIndex);
        }
        pledgeByIndex[pledgeIndex] = Pledge(tokenIds[i], msg.sender);
        emit LogNewPledge(msg.sender, tokenIds[i], pledgeIndex);
        _checkIfTargetHit();
      } else
        return true;
    }
    return true;
  }

  function _checkIfTargetHit()
  internal {
    if (totalPledged == getTarget())
      targetHit = true;
  }

  function getTarget()
  public
  view
  returns (uint) {
    return (pepes.totalSupply() * targetVote / percentPrecision);
  }

  // Burn floors
  function burnFloors(uint[] memory tokenIds)
  public
  onlyOwner
  returns (bool) {
    require(targetHit, "Target not hit");
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

