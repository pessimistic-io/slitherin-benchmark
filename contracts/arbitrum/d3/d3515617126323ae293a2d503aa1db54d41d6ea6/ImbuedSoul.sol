//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./ImbuedSoulContracts.sol";

contract ImbuedSoul is Initializable, ImbuedSoulContracts {

    function initialize() external initializer {
        ImbuedSoulContracts.__ImbuedSoulContracts_init();
    }

    function safeMint(
        address _to,
        uint256 _generation,
        LifeformClass _lifeformClass,
        OffensiveSkill _offensiveSkill,
        SecondarySkill[] calldata _secondarySkills,
        bool _isLandOwner)
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
            _isLandOwner);

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
}
