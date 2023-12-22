//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./StringsUpgradeable.sol";

import "./ImbuedSoulContracts.sol";
import "./BBase64.sol";

contract ImbuedSoul is Initializable, ImbuedSoulContracts {

    using StringsUpgradeable for uint256;

    function initialize() external initializer {
        ImbuedSoulContracts.__ImbuedSoulContracts_init();
    }

    function setImageURI(string calldata _imageURI) external onlyAdminOrOwner {
        imageURI = _imageURI;
    }

    function setTraitStrings(
        string calldata _category,
        uint8[] calldata _traits,
        string[] calldata _strings)
    external
    onlyAdminOrOwner
    {
        require(_traits.length == _strings.length, "ImbuedSoul: Invalid array lengths");

        for(uint256 i = 0; i < _traits.length; i++) {
            if(compareStrings(_category, "Class")) {
                classToString[LifeformClass(_traits[i])] = _strings[i];
            } else if(compareStrings(_category, "Offensive Skill")) {
                offensiveSkillToString[OffensiveSkill(_traits[i])] = _strings[i];
            } else if(compareStrings(_category, "Secondary Skill")) {
                secondarySkillToString[SecondarySkill(_traits[i])] = _strings[i];
            } else {
                revert("ImbuedSoul: Invalid category");
            }
        }
    }

    function safeMint(
        address _to,
        uint256 _generation,
        LifeformClass _lifeformClass,
        OffensiveSkill _offensiveSkill,
        SecondarySkill[] calldata _secondarySkills,
        bool _isLandOwner,
        uint256 _lifeformID)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    {
        uint256 _tokenId = tokenIdCur;
        tokenIdCur++;
        _safeMint(_to, _tokenId);

        tokenIdtoInfo[_tokenId] = ImbuedSoulInfo(
            _generation,
            _lifeformClass,
            _offensiveSkill,
            _secondarySkills,
            _isLandOwner,
            _lifeformID);

        emit ImbuedSoulCreate(_to, _tokenId, tokenIdtoInfo[_tokenId]);
    }

    function burn(uint256 _tokenId)
    external
    override
    whenNotPaused
    onlyAdminOrOwner
    {
        _burn(_tokenId);
    }

    function tokenURI(uint256 _tokenId) public view override returns(string memory) {
        require(_exists(_tokenId), "ImbuedSoul: Token does not exist");
        ImbuedSoulInfo memory _info = tokenIdtoInfo[_tokenId];

        bytes memory _beginningJSON = _getBeginningJSON(_tokenId);
        string memory _attributes = _getAttributes(_info);

        return string(
            abi.encodePacked(
                'data:application/json;base64,',
                BBase64.encode(
                    bytes(
                        abi.encodePacked(
                            _beginningJSON,
                            _attributes,
                            '}'
                        )
                    )
                )
            )
        );
    }

    function _getBeginningJSON(uint256 _tokenId) private view returns(bytes memory) {
        return abi.encodePacked(
            '{"name":"Imbued Soul #',
            _tokenId.toString(),
            '", "description":"Character primitives evolved from the Seed of Life, Imbued Souls are the composable life forms originated in the land of Phanes. Every Imbued Soul has equal governance rights over LifeDAO.", "image": "',
            imageURI,
            '",');
    }

    function _getAttributes(ImbuedSoulInfo memory _info) private view returns(string memory) {
        return string(abi.encodePacked(
            '"attributes": [',
                _getJSONAttributes(_info),
            ']'
        ));
    }

    function _getJSONAttributes(ImbuedSoulInfo memory _info) private view returns(string memory) {
        return string(abi.encodePacked(
            _getClassJSON(_info.lifeformClass), ',',
            _getOffensiveSkillJSON(_info.offensiveSkill), ',',
            _getFirstSecondarySkillJSON(_info.secondarySkills),
            _getSecondSecondarySkillJSON(_info.secondarySkills),
            _getIsLandOwnerJSON(_info.isLandOwner)
        ));
    }

    function _getClassJSON(LifeformClass _class) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"Class","value":"',
            classToString[_class],
            '"}'
        ));
    }

    function _getOffensiveSkillJSON(OffensiveSkill _offensiveSkill) private view returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"Offensive Skill","value":"',
            offensiveSkillToString[_offensiveSkill],
            '"}'
        ));
    }

    function _getIsLandOwnerJSON(bool _isLandOwner) private pure returns(string memory) {
        return string(abi.encodePacked(
            '{"trait_type":"Land Owner","value":"',
            _isLandOwner ? "Yes" : "No",
            '"}'
        ));
    }

    function _getFirstSecondarySkillJSON(SecondarySkill[] memory  _secondarySkills) private view returns(string memory) {
        string memory _secondarySkillName;
        if(_secondarySkills.length > 0) {
            _secondarySkillName = secondarySkillToString[_secondarySkills[0]];
        } else {
            return "";
        }

        return string(abi.encodePacked(
            '{"trait_type":"Secondary Skill","value":"',
            _secondarySkillName,
            '"},'
        ));
    }

    function _getSecondSecondarySkillJSON(SecondarySkill[] memory  _secondarySkills) private view returns(string memory) {
        string memory _secondarySkillName;
        if(_secondarySkills.length > 1) {
            _secondarySkillName = secondarySkillToString[_secondarySkills[1]];
        } else {
            return "";
        }

        return string(abi.encodePacked(
            '{"trait_type":"Secondary Skill","value":"',
            _secondarySkillName,
            '"},'
        ));
    }
}
