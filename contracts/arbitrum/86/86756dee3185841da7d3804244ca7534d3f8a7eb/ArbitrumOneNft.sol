pragma solidity ^0.8.0;

import "./ONFT721.sol";

contract ArbitrumOneNft is ONFT721 {

	constructor(
		string memory _name,
		string memory _symbol,
		uint256 _minGasToTransfer,
		address _lzEndpoint
	) ONFT721(_name, _symbol, _minGasToTransfer, _lzEndpoint) {
		string  memory one = "one";
	}

	function oneContract(string calldata test) external {

	}
}

