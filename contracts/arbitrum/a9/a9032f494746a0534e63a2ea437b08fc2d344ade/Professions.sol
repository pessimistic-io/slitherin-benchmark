pragma solidity ^0.8.13;

import "./console.sol";
import "./Ownable.sol";
import "./SafeMath.sol";

interface IArcane {
    function ownerOf(uint256 tokenId) external returns (address);
}

contract Professions is Ownable {
    IArcane public ARCANE;
    using SafeMath for uint256;

    // NOT 0 based
    mapping(uint256 => uint256) public professions;
    mapping(uint256 => uint256[5]) public specs;
    mapping(uint256 => uint256) public points;
    mapping(uint256 => uint256) public lvlThresholds;
    address public crafting;

    modifier isOwner(uint256 _wizId) {
        require(ARCANE.ownerOf(_wizId) == msg.sender,"Not owner");
        _;
    }

    function chooseProfession(
        uint256 _wizId,
        uint256 _professionId
    ) external isOwner(_wizId) {
        require(professions[_wizId] == 0, "Already chose profession");
        professions[_wizId] = _professionId;
    }

    function chooseSpec(
        uint256 _wizId,
        uint256 _specTier,
        uint256 _spec
    ) external isOwner(_wizId) {
        require(professions[_wizId] > 0, "Choose profession first");
        require(specs[_wizId][_specTier] == 0, "Already chosen");
        require(getLevel(_wizId) >= _specTier * 2, "Not enough experience");
        require(
            (_spec == 1 && _specTier < 5) || (_spec == 2 && _specTier < 5),
            "Spec has to be 1 or 2"
        );
        specs[_wizId][_specTier] = _spec;
    }

    function earnXP(uint256 _wizId, uint256 _points) public {
        require(msg.sender == crafting);
        points[_wizId]+=_points;
    }

    function getProfession(
        uint256 _wizId
    )
        external
        view
        returns (
            uint256 profId,
            uint256[5] memory currSpecs,
            uint256 currPoints
        )
    {
        return (professions[_wizId], specs[_wizId], points[_wizId]);
    }

    function checkSpec(
        uint256 _wizId,
        uint256 _specStructureId
    ) public view returns (bool) {
        uint256 zoneId = (_specStructureId % 1500).div(20);
        if (professions[_wizId] == zoneId + 1) {
            uint256 specId = (_specStructureId % 1500) - 20 * zoneId;
            uint256 tier = (specId - 1).div(2);
            uint256 unlockId = 2 - (specId % 2);
            if (specs[_wizId][tier] == unlockId) {
                return true;
            }
        }
        return false;
    }

    // 0 based
    function getLevel(uint256 _wizId) public view returns (uint256) {
        for (uint i = 1; i < 15; i++) {
            if (points[_wizId] < lvlThresholds[i]) {
                return i - 1;
            }
        }
        return 0;
    }

    function setData(address _arcane, address _crafting, uint256[] memory _lvlThresholds) external onlyOwner{
        ARCANE = IArcane(_arcane);
        crafting=_crafting;
        for(uint256 i=0;i<_lvlThresholds.length;i++){
            lvlThresholds[i] = _lvlThresholds[i];
        }
    }
    
}

