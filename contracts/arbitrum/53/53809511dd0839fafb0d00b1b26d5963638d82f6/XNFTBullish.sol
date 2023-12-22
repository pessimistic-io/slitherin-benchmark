// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.8.17;

//---------------------------------------------------------
// Imports
//---------------------------------------------------------
import "./XNFTBase.sol";

//---------------------------------------------------------
// Contract
//---------------------------------------------------------
contract XNFTBullish is XNFTBase
{
	constructor() XNFTBase("bafybeidajqcl52q4jlk7dz3wzfj4f665x6mzdjer5abzeh4ib7p6dz6cme")
	{
		address_operator = msg.sender;
	}
}

