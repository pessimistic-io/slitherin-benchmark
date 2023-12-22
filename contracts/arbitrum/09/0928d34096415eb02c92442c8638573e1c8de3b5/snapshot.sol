//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./IERC721.sol";



contract NFTSnapshot is Ownable{
    IERC721 public nftContract;
    
    mapping(address => uint256) public snapshot;
    
    constructor(address _nftContract) {
        nftContract = IERC721(_nftContract);
    }
    
    function takeSnapshot() public onlyOwner {
        uint256 totalSupply = 48001;
        for (uint256 i = 1; i < totalSupply; i++) {
            address owner = nftContract.ownerOf(i);
            snapshot[owner] += 1;
        }
    }
}
