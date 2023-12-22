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
pragma solidity ^0.8.13;

import "./Ownable.sol";
import "./SafeMath.sol";

interface IArcane {
    function ownerOf(uint256 tokenId) external returns (address);
}

interface IAdventure {
    function getWizardLevel(
        uint256 _wizId
    ) external view returns (uint256 level);
}

contract Battleskills is Ownable {
    using SafeMath for uint256;

    IArcane public ARCANE;
    IAdventure public ADVENTURE;
    address public RESET;
    mapping(uint256 => mapping(uint256 => uint256)) public skills;

    modifier isOwner(uint256 _wizId) {
        require(ARCANE.ownerOf(_wizId) == msg.sender, "Not owner");
        _;
    }

    function chooseSkill(
        uint256 _wizId,
        uint256 _skillId
    ) external isOwner(_wizId) {
        require(_skillId < 6, "Wrong skillId");
        uint256 tier = (_skillId / 2) + 1;
        require(skills[_wizId][tier] == 0, "Already chosen");
        uint256 wizLvl = ADVENTURE.getWizardLevel(_wizId);
        require(wizLvl.div(3) >= tier, "Not enough XP");
        skills[_wizId][tier] = (_skillId % 2) + 1;
    }

    function resetSkills(uint256 _wizId) external {
        require(msg.sender == RESET);
        for (uint i = 0; i < 6; i++) {
            skills[_wizId][i] = 0;
        }
    }

    function getSkills(uint256 _wizId) public view returns (uint256[6] memory) {
        uint256[6] memory battleSkills;
        for (uint i = 0; i < 6; i++) {
            battleSkills[i] = skills[_wizId][i];
        }
        return battleSkills;
    }

    function setData(
        address _arcane,
        address _adventure,
        address _reset
    ) external onlyOwner {
        ARCANE = IArcane(_arcane);
        ADVENTURE = IAdventure(_adventure);
        RESET = _reset;
    }
}

