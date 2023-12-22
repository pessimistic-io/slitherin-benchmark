//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./MerkleProof.sol";
import "./Strings.sol";

contract DPSPirateFeatures is Ownable {
    bytes32 public merkleRoot;
    string public merkleLink;

    string[] private traitsNames;
    string[] private skillsNames;

    mapping(uint16 => string[8]) traitsPerPirate;
    mapping(uint16 => uint16[3]) skillsPerPirate;

    constructor() {
        traitsNames = ["Uniform", "Hat", "Peg Leg", "Feathers", "Eyes", "Earring", "Beak", "Background"];
        skillsNames = ["Luck", "Navigation", "Strength"];
    }

    /**
     * @dev initialize in batches
     */
    function initialSkillsAndTraitsBatch(
        bytes32[] calldata _leafs,
        bytes32[][] calldata _merkleProofs,
        uint16[] calldata _dpsIds,
        string[][] calldata _traits,
        uint16[][] calldata _skills
    ) external onlyOwner {
        for (uint256 i = 0; i < _leafs.length; i++) {
            initialSkillsAndTraits(_leafs[i], _merkleProofs[i], _dpsIds[i], _traits[i], _skills[i]);
        }
    }

    function initialSkillsAndTraits(
        bytes32 _leaf,
        bytes32[] calldata _merkleProof,
        uint16 _dpsId,
        string[] calldata _traits,
        uint16[] calldata _skills
    ) internal {
        string memory concatenatedTraits = string(
            abi.encodePacked(
                string(abi.encodePacked(_traits[0], _traits[1], _traits[2], _traits[3], _traits[4])),
                _traits[5],
                _traits[6],
                _traits[7]
            )
        );

        string memory concatenatedSkills = string(
            abi.encodePacked(Strings.toString(_skills[0]), Strings.toString(_skills[1]), Strings.toString(_skills[2]))
        );
        bytes32 node = keccak256(abi.encodePacked(_dpsId, concatenatedTraits, concatenatedSkills));

        require(node == _leaf, "Leaf not matching the node");
        require(MerkleProof.verify(_merkleProof, merkleRoot, _leaf), "Invalid proof.");

        string[8] memory traits;
        traits[0] = _traits[0];
        traits[1] = _traits[1];
        traits[2] = _traits[2];
        traits[3] = _traits[3];
        traits[4] = _traits[4];
        traits[5] = _traits[5];
        traits[6] = _traits[6];
        traits[7] = _traits[7];

        uint16[3] memory skills;
        skills[0] = _skills[0];
        skills[1] = _skills[1];
        skills[2] = _skills[2];
        traitsPerPirate[_dpsId] = traits;
        skillsPerPirate[_dpsId] = skills;
    }

    function getTraitsAndSkills(uint16 _dpsId) external view returns (string[8] memory, uint16[3] memory) {
        return (traitsPerPirate[_dpsId], skillsPerPirate[_dpsId]);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
    }

    function setMerkleTreeLink(string calldata _link) external onlyOwner {
        merkleLink = _link;
    }
}

