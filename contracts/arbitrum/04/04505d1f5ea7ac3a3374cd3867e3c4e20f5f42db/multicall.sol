// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0; 
 
import "./Pausable.sol";
import "./Ownable.sol";
 
contract Multicall is Ownable, Pausable { 
    constructor() {} 
 
    function multicall( 
        address[] memory reciptions, 
        uint256 amount 
    ) public payable whenNotPaused onlyOwner { 
        uint256 len = reciptions.length; 
        while (len != 0) { 
            (bool _status, ) = payable(reciptions[len - 1]).call{value: amount}( 
                "" 
            ); 
            require(_status, "Transfer failed"); 
            len--; 
        } 
    } 
 
    /** 
    @dev Pause the contract 
     */ 
    function pause() public onlyOwner { 
        _pause(); 
    } 
 
    /** 
    @dev Unpause the contract 
     */ 
    function unpause() public onlyOwner { 
        _unpause(); 
    } 
}
