pragma solidity ^0.4.24;

import "./CappedCrowdsale.sol";

contract QuestBoardCrowdSale is CappedCrowdsale {
    uint256 internal constant ethCap = 7000 ether;
    uint256 internal constant oneEthToTokens = 50000;
    
    constructor(address _wallet, ERC20 _token) public
        Crowdsale(oneEthToTokens, _wallet, _token)
        CappedCrowdsale(ethCap)
    {
        
    }
}
