// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./ERC721Enumerable.sol";
import "./INpcDesc.sol";

contract ArbitrumNPCs is ERC721Enumerable, Ownable {

 mapping(uint256 => uint256) internal seeds;
 INpcDesc public desc;
 uint256 public maxSupply = 10000;
 bool public live = true;
 string public cost = "free";
 string public maxPperWallet = "100 NPCs per wallet";

 constructor(INpcDesc newDesc) ERC721("Arbitrum NPC", "ANPC") {
 desc = newDesc;
 }

 function setLive(bool value) external onlyOwner {
 live = value;
 }

 function tokenURI(uint256 tokenId) public view returns (string memory) {
 require(_exists(tokenId), "[X_X]");
 uint256 seed = seeds[tokenId];
 return desc.tokenURI(tokenId, seed);
 }

function generateSeed(uint256 tokenId) private view returns (uint256) {
 uint256 r = random(tokenId);
 uint256 headSeed = 100 * (r % 7 + 10) + ((r >> 48) % 20 + 10);
 uint256 bodySeed = 100 * ((r >> 96) % 6 + 10) + ((r >> 96) % 20 + 10);
 uint256 legsSeed = 100 * ((r >> 144) % 7 + 10) + ((r >> 144) % 20 + 10);
 uint256 feetSeed = 100 * ((r >> 192) % 2 + 10) + ((r >> 192) % 20 + 10);
 return 10000 * (10000 * (10000 * headSeed + bodySeed) + legsSeed) + feetSeed;
 }

 function random(uint256 tokenId) private view returns (uint256 pseudoRandomness) {
 pseudoRandomness = uint256(
 keccak256(abi.encodePacked(blockhash(block.number - 1), tokenId))
 );

 return pseudoRandomness;
 }

  function setDesc(INpcDesc newDesc) external onlyOwner {
 desc = newDesc;
 }

  function mint(uint32 count) external payable {
 require(live, "(X_X)");
 require(count < 100, "(-_-)");
 uint256 nextTokenId = _owners.length;
 unchecked {
 require(nextTokenId + count < maxSupply, "(0_0)");
 }

 for (uint32 i; i < count;) {
 seeds[nextTokenId] = generateSeed(nextTokenId);
 _mint(_msgSender(), nextTokenId);
 unchecked { ++nextTokenId; ++i; }
 }
 }

  function burn(uint256 tokenId) public {
 require(_isApprovedOrOwner(_msgSender(), tokenId), "[0_-]");
 delete seeds[tokenId];
 _burn(tokenId);
 }

 function withdraw() external payable onlyOwner {
 (bool os,)= payable(owner()).call{value: address(this).balance}("");
 require(os);
 }

}

