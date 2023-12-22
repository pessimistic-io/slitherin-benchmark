pragma solidity 0.8.9;

import "./OFT.sol";

contract OmnichainToken is OFT {
	constructor(address _lzEndpoint) OFT('Omnichain Token', 'OT', _lzEndpoint) {}
}

