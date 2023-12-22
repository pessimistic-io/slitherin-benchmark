// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./MechaPunkx.sol";
import "./Ownable.sol";
import "./ERC20.sol";
import "./ERC20Burnable.sol";

/*
******************************
********* MECH TOKEN *********
******************************

MECH Token is an ERC20 that yields on a schedule to owners of MechaPunkx NFTs
*/
contract MechToken is ERC20, ERC20Burnable, Ownable {

	uint256 public startTime = block.timestamp;

	MechaPunkx private MechaPunkxNFT;

	// Map NFT ID to MECH claimed, resets on NFT transfer, "offset" is a better name
	mapping(uint256 => uint256) private claimed;

	constructor(address mAddress) ERC20("MECH Token", "MECH") { 
		MechaPunkxNFT = MechaPunkx(mAddress);
	}
	
	// Tokens stop existing when they are burned
	function tokenExists(uint256 tokenId) public view returns (bool) {
		return MechaPunkxNFT.exists(tokenId);
	}

	// Returns max amount of MECH earned by any single NFT minted day 0, at a rate of 1 MECH / DAY
	function maxEarned() public view returns (uint256) {   
		uint nDays = (block.timestamp - startTime) / 1 days;
		return nDays;
	}

	// Set the claimed amount equal to the max possible, effectively setting the pending balance to zero
	// When an address sells or transfers NFT, reset again for the new owner
	function startEarning(uint256 tokenId) external onlyOwner {
		claimed[tokenId] = maxEarned();
	}

	// MECH token balance accumulating
	function pendingBalance(uint256 tokenId) public view returns (uint256) {
		require(tokenExists(tokenId), "tokenId does not exist");
		return maxEarned() - claimed[tokenId];
	}

	// Set limiting schedule to make distribution fair (limits compounding)
	function claimUpperBound() public view returns (uint256) {
		
		uint day = maxEarned();

		if (day > 141) {
			uint wks = (day - 141) / 7;
			return 1208 + (100 * wks);
		}

		uint256[2][17] memory milestones;
		milestones[0] = [uint256(141),uint256(1208)];
		milestones[1] = [uint256(135),uint256(1106)];
		milestones[2] = [uint256(128),uint256(994)];
		milestones[3] = [uint256(122),uint256(904)];
		milestones[4] = [uint256(114),uint256(806)];
		milestones[5] = [uint256(107),uint256(702)];
		milestones[6] = [uint256(98),uint256(594)];
		milestones[7] = [uint256(89),uint256(495)];
		milestones[8] = [uint256(80),uint256(405)];
		milestones[9] = [uint256(71),uint256(324)];
		milestones[10] = [uint256(62),uint256(252)];
		milestones[11] = [uint256(53),uint256(189)];
		milestones[12] = [uint256(44),uint256(135)];
		milestones[13] = [uint256(35),uint256(90)];
		milestones[14] = [uint256(26),uint256(54)];
		milestones[15] = [uint256(17),uint256(27)];
		milestones[16] = [uint256(8),uint256(9)];

		for (uint8 i = 0; i < milestones.length; i++) {
			if (day >= milestones[i][0]) {
				return milestones[i][1];
			}
		}

		return 0;
	} 

	// Returns claimable amount, according to schedule
	// Can return value higher than 1 per day, schedule has an upper bound on compounding
	// "Claimable" means "allowed to claim up to this amount if earned", and is not "the amount earned"
	function claimableBalance(uint256 tokenId) public view returns (uint256) {
		require(tokenExists(tokenId), "tokenId does not exist");
		uint256 amountCanClaim = claimUpperBound();
		uint256 amountClaimed = claimed[tokenId];

		// Because "claimed" resets to maxEarned value on transfer, value can exceed the claim upper bound
		if (amountClaimed >= amountCanClaim) {
			return 0;
		}
		return amountCanClaim - amountClaimed;
	}

	// Update MECH balance of NFT (owned by caller)
	function claim(uint256 tokenId) external onlyOwner {
		require(tokenExists(tokenId), "tokenId does not exist");
		uint256 p = pendingBalance(tokenId);
		uint256 canClaim = claimableBalance(tokenId);

		if (canClaim > p) {
			canClaim = p;
		}

		if (canClaim > 0) {
			claimed[tokenId] += canClaim;
			address owner = MechaPunkxNFT.ownerOf(tokenId);
			_mint(owner, canClaim * (10**18));
		}
	}

	
	// Before burning NFT, give some MECH back to the user for minting
	function burnNFT(uint256 tokenId, address owner) external onlyOwner {
		require(tokenExists(tokenId), "tokenId does not exist");
		
		uint256 rebate = 1 * (10**18);

		if (maxEarned() >= 10) {
			rebate = (MechaPunkxNFT.mintCost() * (10**18)) / 2;
		}
		
		_mint(owner, rebate);
	}
	
}
