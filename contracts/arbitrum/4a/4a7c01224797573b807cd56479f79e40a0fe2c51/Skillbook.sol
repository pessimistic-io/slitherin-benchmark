//        _.--._  _.--._
//  ,-=.-":;:;:;\':;:;:;"-._
//  \\\:;:;:;:;:;\:;:;:;:;:;\
//   \\\:;:;:;:;:;\:;:;:;:;:;\
//    \\\:;:;:;:;:;\:;:;:;:;:;\
//     \\\:;:;:;:;:;\:;::;:;:;:\
//      \\\;:;::;:;:;\:;:;:;::;:\
//       \\\;;:;:_:--:\:_:--:_;:;\    
//        \\\_.-"      :      "-._\
//         \`_..--""--.;.--""--.._=>
//          "
//-shimrod
//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./Ownable.sol";


interface IArcane {
    function checkIfConnected(address _sender) external returns (bool);

    function renounceWizard(uint256 _wizId, address _caller) external;
}

contract Skillbook is Ownable {

    IArcane public ARCANE;

    struct Book{
        uint16 mana;
        uint256[5] skills;
    }

    mapping (uint256=> Book) public wizToBook;
     // @dev the last timestamp mana was used
    mapping (uint256 => uint256) public lastManaUse;
    uint256 public manaRefillTime = 1 days;
    uint16 private MANA_PER_HOUR = 10;
    uint16 private MAX_MANA = 240;

    event SkillsImproved(uint256 wizId, uint256[5] skillsAdded);
    event NewSkillbook(uint256 wizId, uint256[5] startSkills);
    event ManaUsed(uint256 wizardId, uint256 manaUsed);

    modifier isConnected() {
        require(ARCANE.checkIfConnected(msg.sender) || IArcane(msg.sender) == ARCANE, "No authority" );
        _;
    }

    // EXTERNAL
    // ------------------------------------------------------

    function improveSkills(uint256[5] memory _toAdd, uint256 _wizId) external isConnected{
        for(uint256 i=0;i<5;i++){
            wizToBook[_wizId].skills[i] += _toAdd[i];
        }
        
        emit SkillsImproved(_wizId, _toAdd);
    }

    function createBook(uint256[5] memory _startSkills, uint256 _wizId) external isConnected{
         for(uint256 i=0;i<5;i++){
            wizToBook[_wizId].skills[i] = _startSkills[i];
        }
        wizToBook[_wizId].mana = MAX_MANA;
        lastManaUse[_wizId] = block.timestamp;

        emit NewSkillbook(_wizId,_startSkills);
    }

    // @dev returns a bool if Wizard has enough mana to perform action
    function useMana(uint8 _amount, uint256 _wizId) external isConnected returns(bool) {
        // Update regenerated mana
        wizToBook[_wizId].mana += _getManaGenerated(_wizId); 
        if(wizToBook[_wizId].mana>MAX_MANA){
            wizToBook[_wizId].mana = MAX_MANA;
        }

        // use required mana
        if(wizToBook[_wizId].mana < _amount){
            return false;
        }else{
            wizToBook[_wizId].mana -= _amount;
            lastManaUse[_wizId]=block.timestamp;
            emit ManaUsed(_wizId, _amount);
            return true;
        }
    }

    function getWizardSkills(uint256 _wizId) external view returns (uint256[5] memory){
        uint256[5] memory skills;
        for(uint256 i=0;i<5;i++){
            skills[i] = wizToBook[_wizId].skills[i];
        }
        return skills;
    }

    function getMana(uint256 _wizId) external view returns(uint16){
        return wizToBook[_wizId].mana+_getManaGenerated(_wizId);
    }


    // INTERNAL
    // ------------------------------------------------------

    function _getManaGenerated(uint256 _wizId) internal view returns (uint16){
         uint256 elapsed = block.timestamp-lastManaUse[_wizId];
        uint16 manaRegenerated = 0;
        while(elapsed>=3600){
            elapsed -= 3600;
            manaRegenerated+=MANA_PER_HOUR;
        }
        return manaRegenerated;
    }

    // OWNER
    // ------------------------------------------------------

    function setArcane(address _arcaneAddress) external onlyOwner {
        ARCANE = IArcane(_arcaneAddress);
    }
}
