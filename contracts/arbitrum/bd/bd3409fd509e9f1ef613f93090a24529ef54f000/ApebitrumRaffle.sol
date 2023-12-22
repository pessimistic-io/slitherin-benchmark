//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./Ownable.sol";

contract ApebitrumRaffle is Ownable {
  event LuckyWinnerPicked(uint256 tokenId);

  uint256[] public pickedTokenIds;

  constructor() {
  }

  function pickWinner(uint256 tokenId) public onlyOwner {
    uint256 randomNum = uint256(
      keccak256(
        abi.encode(
          address(this),
          block.number,
          block.timestamp,
          block.difficulty,
          blockhash(block.number - 1),
          tx.gasprice,
          tokenId
        )
      )
    );

    uint256 luckyTokenId = (randomNum % 4545) + 1;

    pickedTokenIds.push(luckyTokenId);

    emit LuckyWinnerPicked(luckyTokenId);
  }

  function getAllPickedTokenId() public view returns (uint256[] memory) {
    uint256 len = pickedTokenIds.length;
    uint256[] memory ret = new uint256[](len);
    for (uint i = 0; i < len; i++)
      ret[i] = pickedTokenIds[i];
    return ret;
  }
}

