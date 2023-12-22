// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./LibEnvelopTypes.sol";
interface IWrapperV1URI  {

function getOriginalURI(address _wNFTAddress, uint256 _wNFTTokenId) 
        external 
        view 
        returns(string memory); 

 function getWrappedToken(address _wNFTAddress, uint256 _wNFTTokenId) 
        external 
        view 
        returns (ETypes.WNFT memory);
}


