// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Initializable.sol";
import "./ERC721Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./AdminableUpgradeable.sol";

contract StarState is
    Initializable,
    ERC721Upgradeable,
    PausableUpgradeable,
    AdminableUpgradeable
{
    mapping(uint256 => uint256) private _starExperience;
    mapping(uint256 => uint256) private _starStoryTimestamp;
    mapping(uint256 => bool) private _starSpiritIsSummoned;

    event StarMetadataUpdated(
        uint256 indexed _tokenId,
        uint256 experience,
        uint256 storyTimestamp,
        bool spiritIsSummoned
    );

    event MetadataUpdate(uint256 _tokenId);

    function __StarState_init() internal onlyInitializing {
        __ERC721_init("Star", unicode"★");
        __Pausable_init();
        __Ownable_init();
        __Adminable_init();
    }

    function getStarExperience(uint256 _tokenId) public view returns (uint256) {
        return _starExperience[_tokenId];
    }

    function getStarStoryTimeStamp(
        uint256 _tokenId
    ) public view returns (uint256) {
        return _starStoryTimestamp[_tokenId];
    }

    function getStarSpiritIsSummoned(
        uint256 _tokenId
    ) public view returns (bool) {
        return _starSpiritIsSummoned[_tokenId];
    }

    function addStarExperience(
        uint256 _tokenId,
        uint256 _experience
    ) external onlyAdminOrOwner {
        _requireMinted(_tokenId);
        _starExperience[_tokenId] += _experience;
        emit StarMetadataUpdated(
            _tokenId,
            _starExperience[_tokenId],
            _starStoryTimestamp[_tokenId],
            _starSpiritIsSummoned[_tokenId]
        );
        emit MetadataUpdate(_tokenId);
    }

    function setStarSpiritIsSummoned(
        uint256 _tokenId,
        bool _isSummoned
    ) external onlyAdminOrOwner {
        _requireMinted(_tokenId);
        _starSpiritIsSummoned[_tokenId] = _isSummoned;
        emit StarMetadataUpdated(
            _tokenId,
            _starExperience[_tokenId],
            _starStoryTimestamp[_tokenId],
            _starSpiritIsSummoned[_tokenId]
        );
        emit MetadataUpdate(_tokenId);
    }

    function setStarStoryTimeStamp(uint256 _tokenId) external whenNotPaused {
        require(_isApprovedOrOwner(_msgSender(), _tokenId), "ERC721: caller is not token owner or approved");
        
        _starStoryTimestamp[_tokenId] = block.timestamp;
        emit StarMetadataUpdated(
            _tokenId,
            _starExperience[_tokenId],
            _starStoryTimestamp[_tokenId],
            _starSpiritIsSummoned[_tokenId]
        );
        emit MetadataUpdate(_tokenId);
    }
}

