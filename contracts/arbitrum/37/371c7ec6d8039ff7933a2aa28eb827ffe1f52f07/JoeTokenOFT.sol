pragma solidity ^0.8.0;

import "./OFTWithFee.sol";

contract JoeTokenOFT is OFTWithFee {
    constructor(address _lzEndpoint) OFTWithFee("JoeToken", "JOE", 8, _lzEndpoint){}
}
