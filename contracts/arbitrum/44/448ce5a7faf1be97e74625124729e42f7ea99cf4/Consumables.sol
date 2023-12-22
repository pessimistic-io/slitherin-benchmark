pragma solidity ^0.8.0;

import "./Ownable.sol";

contract Consumables is Ownable{

    mapping (address => bool) public whitelisted;

    mapping (uint256 => uint256) public manaPotions;
    mapping (uint256 => uint256) public stats_Focus;
    mapping (uint256 => uint256) public stats_Strength;
    mapping (uint256 => uint256) public stats_Intellect;
    mapping (uint256 => uint256) public stats_Spell;
    mapping (uint256 => uint256) public stats_Endurance;
    mapping (uint256 => uint256) public giantLeap;
    mapping (uint256 => uint256) public guaranteed;

    modifier isWhitelisted(){
        require(whitelisted[msg.sender], "Consumables call not whitelisted");
        _;
    }

    function getBonus (uint256 _wizId, uint256 _bonusId) external isWhitelisted returns(uint256) {
        uint256 toReturn = 0;
        if(_bonusId==0 && manaPotions[_wizId]>0){
            toReturn = manaPotions[_wizId];
            manaPotions[_wizId]=0;
        }else if(_bonusId==1 && stats_Focus[_wizId]>0){
            toReturn = stats_Focus[_wizId];
            stats_Focus[_wizId]=0;
        }else if(_bonusId==2 && stats_Strength[_wizId]>0){
            toReturn = stats_Strength[_wizId];
            stats_Strength[_wizId]=0;
        }else if(_bonusId==3 && stats_Intellect[_wizId]>0){
            toReturn = stats_Intellect[_wizId];
            stats_Intellect[_wizId]=0;
        }else if(_bonusId==4 && stats_Spell[_wizId]>0){
            toReturn = stats_Spell[_wizId];
            stats_Spell[_wizId]=0;
        }else if(_bonusId==5 && stats_Endurance[_wizId]>0){
            toReturn = stats_Endurance[_wizId];
            stats_Endurance[_wizId]=0;
        }else if(_bonusId==6 && giantLeap[_wizId]>0){
            toReturn = giantLeap[_wizId];
            giantLeap[_wizId]=0;
        }else if(_bonusId==7 && guaranteed[_wizId]>0){
            toReturn = guaranteed[_wizId];
            guaranteed[_wizId]=0;
        }
        return toReturn;
    }

    function giveBonus(uint256 _wizId, uint256 _bonusId, uint256 _amount) external isWhitelisted {
       
        if(_bonusId==0){
            manaPotions[_wizId]+=_amount;
        }else if(_bonusId==1){
            stats_Focus[_wizId]+=_amount;
        }else if(_bonusId==2){
            stats_Strength[_wizId]+=_amount;
        }else if(_bonusId==3){
            stats_Intellect[_wizId]+=_amount;
        }else if(_bonusId==4){
            stats_Spell[_wizId]+=_amount;
        }else if(_bonusId==5){
            stats_Endurance[_wizId]+=_amount;
        }else if(_bonusId==6){
            giantLeap[_wizId]+=_amount;
        }else if(_bonusId==7){
            guaranteed[_wizId]+=_amount;
        }
    }

    function setWhitelisted(address _toWhitelist) external onlyOwner{
        whitelisted[_toWhitelist]=true;
    }


    function removeWhitelisted(address _toRemove) external onlyOwner{
        whitelisted[_toRemove]=false;
    }

}
