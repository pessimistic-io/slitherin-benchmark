// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.17;

//---------------------------------------------------------
// Imports
//---------------------------------------------------------
import "./XNFTBase.sol";

//---------------------------------------------------------
// Contract
//---------------------------------------------------------
contract XNFTHorn is XNFTBase
{
	constructor() XNFTBase("bafybeie5myseb3ycbtwl7y3kzl2c2tfz4sabd6v35zjfzycy7j7354ixju")
	{
		address_operator = msg.sender;
	}
}

