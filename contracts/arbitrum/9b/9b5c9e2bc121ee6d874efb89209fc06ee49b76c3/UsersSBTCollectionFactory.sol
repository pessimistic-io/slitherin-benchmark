// SPDX-License-Identifier: MIT
// Factory for Public Mintable User NFT Collection

pragma solidity 0.8.19;

import "./Ownable.sol";
import "./UsersSBTCollectionProxy.sol";


contract UsersSBTCollectionFactory is  Ownable{

    mapping(address => bool) public factoryOperators;

    constructor(){
        factoryOperators[msg.sender] = true;
    }

    function deployProxyFor(
        address _implAddress, 
        address _creator,
        string memory name_,
        string memory symbol_,
        string memory _baseurl,
        address _wrapper
    ) public returns(address proxy) 
    {
        require(factoryOperators[msg.sender], "Only for operator");
        proxy = address(new UsersSBTCollectionProxy(
            _implAddress, 
            _creator,
            name_,
            symbol_,
            _baseurl,
            _wrapper
        ));
    }
    ///////////////////////////////////////////
    /////  Admin functions     ////////////////
    ///////////////////////////////////////////      
    function setOperatorStatus(address _operator, bool _isValid) external onlyOwner {
        factoryOperators[_operator] = _isValid;
    }
}
