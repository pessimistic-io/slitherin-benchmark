// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "./ERC20.sol";
import "./SafeMath.sol";


contract LuckyGem is ERC20 {
    
    using SafeMath for uint256;    

    // treasury wallet
    address public treasury; 
    uint256 public weiPerGEM;
    uint256 public genesisTimestamp;

    constructor() ERC20("LuckyGem", "GEM") { 
        weiPerGEM = 69420; // 10**18 GEM = 69420 wei
        genesisTimestamp = 1689592271; // Mon Jul 17 2023 11:11:11 GMT+0000

        // Set the treasury wallet to the contract owner
        treasury = msg.sender;

    }

    // setter for the treasury wallet
    function setTreasury(address _treasury) public {
        require(msg.sender == treasury, "Only airdrop wallet can set airdrop wallet");
        require(address(this)!= _treasury, "Treasury wallet cannot be the contract address");
        treasury = _treasury;
    }

    // Helper function to generate a random number
    function random() private view returns (uint256) {        
        uint256 randomNumber = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, block.coinbase)));
        uint256 randomNumberInRange = (randomNumber % 100) + 1; // Modulo 100 and add 1 to get a number between 1 and 100
        return randomNumberInRange;
    }

        
    function _isContract(address _address) private view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_address)
        }
        return (size > 0);
    }


    modifier notFromContract() {
        require(!_isContract(msg.sender), "Smart contract transactions not allowed");
        require(msg.sender == tx.origin, "msg.sender != tx.origin");
        _;
    }
    function currentWeiPerGEM() public view returns (uint256){
        // Calculate the current luckyGemPerWei based on time difference
        uint256 timeDifference = block.timestamp.sub(genesisTimestamp);
        uint256 increaseFactor = (timeDifference / 60); // 1 min (60 seconds) to increase 0.01% = 1/10000
        return weiPerGEM + (weiPerGEM * increaseFactor) / 10000;
    }
    
    function miningLuckyGem() public payable notFromContract{
        require(msg.value >= 0.01 ether, "Minimum 0.01 ETH required to mine LuckyGem"); 
        require(genesisTimestamp < block.timestamp, "Mining not started yet");
                                
        uint256 poolShare = 0;
        uint256 treasuryShare = 0;
        // Check if user has a chance to win the eth pool
        if (random() < 10) {

            // Transfer ETH pool to the buyer
            
            poolShare = (address(this).balance * 90) / 100;      
            treasuryShare = address(this).balance - poolShare;      
                        
        }
        else {

             poolShare =0;
             treasuryShare = 0;
        }
        // Transfer ETH pool share to the buyer
        payable(msg.sender).transfer(poolShare);            

        // transfer the remaining 10% to the contract owner
        payable(treasury).transfer(treasuryShare);
        

        // Calculate the amount of GEM to be rewarded
        // 1 GEM (10**18 wei GEM) = currentWeiPerGEM
        // msg.value => msg.value/currentWeiPerGEM  * 10**18 wei GEM
        uint256 luckyReward = (msg.value  * 10 ** 18).div(currentWeiPerGEM());        
        
        // Transfer GEM to the buyer
        _mint(msg.sender, luckyReward);
    }

    fallback() external payable { 
        require(!_isContract(msg.sender), "Smart contract transactions not allowed");
        miningLuckyGem();
    }

}
