//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721Enumerable.sol";
import "./AccessControlEnumerable.sol";
import "./Strings.sol";
import "./Ownable.sol";
import "./IERC721.sol";
import "./SafeERC20.sol";
import "./IERC1155.sol";
import "./DPSStructs.sol";

contract DPSFlagship is ERC721Enumerable, AccessControlEnumerable, Ownable {
    using SafeERC20 for IERC20;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADE_ROLE = keccak256("UPGRADE_ROLE");

    bool mintingStopped = false;

    mapping(uint256 => uint8[7]) private partsPerShip;

    mapping(FLAGSHIP_PART => uint8) public partsOrder;
    string private baseUri = "https://damnedpiratessociety.io/api/tokens/";

    event LockedUrl();
    event UrlChanged(uint256 indexed _id, string newUrl);
    event PartUpgraded(FLAGSHIP_PART indexed _part, uint256 indexed _tokenId, uint8 _level);

    constructor() ERC721("DSP Flagship", "DSPFlagship") {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(UPGRADE_ROLE, _msgSender());
        partsOrder[FLAGSHIP_PART.HEALTH] = 0;
        partsOrder[FLAGSHIP_PART.CANNON] = 1;
        partsOrder[FLAGSHIP_PART.HULL] = 2;
        partsOrder[FLAGSHIP_PART.SAILS] = 3;
        partsOrder[FLAGSHIP_PART.HELM] = 4;
        partsOrder[FLAGSHIP_PART.FLAG] = 5;
        partsOrder[FLAGSHIP_PART.FIGUREHEAD] = 6;
    }

    function mint(address _owner, uint256 _tokenId) external {
        require(hasRole(MINTER_ROLE, _msgSender()), "Does not have role MINTER_ROLE");
        require(!mintingStopped, "Minting has been stopped");

        uint8[7] memory parts;
        parts[0] = 100;
        parts[1] = 1;
        parts[2] = 1;
        parts[3] = 1;
        parts[4] = 1;
        parts[5] = 1;
        parts[6] = 1;
        partsPerShip[_tokenId] = parts;

        _safeMint(_owner, _tokenId);
    }

    /**
     * @notice upgrades a flagship part. The health of the flagship is viewed as a part and it's the index 0.
     * @param _part - FLAGSHIP_PART
     * @param _tokenId - flagshipId
     * @param _level - level that we want to upgrade to
     */
    function upgradePart(
        FLAGSHIP_PART _part,
        uint256 _tokenId,
        uint8 _level
    ) external {
        require(hasRole(UPGRADE_ROLE, _msgSender()), "Does not have role UPGRADE_ROLE");
        require(exists(_tokenId), "Token does not exists");
        if (_part == FLAGSHIP_PART.HEALTH && _level > 100) revert("You can't upgrade Health over 100");
        else if (_part != FLAGSHIP_PART.HEALTH && (_level > 10 || _level == 0)) revert("Level can't be more than 10 or 0");
        partsPerShip[_tokenId][partsOrder[_part]] = _level;
        emit PartUpgraded(_part, _tokenId, _level);
    }

    /**
     * @notice Call this when minting period finishes, it's irreversible, once called the minting can not be enabled
     */
    function changeMinting(bool _stopped) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Does not have role DEFAULT_ADMIN_ROLE");
        mintingStopped = _stopped;
    }

    function isStopped() external view returns (bool) {
        return mintingStopped;
    }

    function setBaseUri(string memory _newBaseUri) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Does not have role DEFAULT_ADMIN_ROLE ");
        baseUri = _newBaseUri;
    }

    function getPartsLevel(uint256 _flagshipId) external view returns (uint8[7] memory) {
        return partsPerShip[_flagshipId];
    }

    function exists(uint256 _tokenId) public view returns (bool) {
        return _exists(_tokenId);
    }

    function tokensOfOwner(address _owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);
        if (tokenCount == 0) {
            // Return an empty array
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = tokenOfOwnerByIndex(_owner, index);
            }
            return result;
        }
    }

    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        require(_exists(_tokenId), "ERC721: URI query for nonexistent token");

        string memory parts;
        uint8[7] memory traitAndLevel = partsPerShip[_tokenId];
        parts = string(
            abi.encodePacked(
                parts,
                '{ "trait_type" : "HEALTH LEVEL", "value" : "',
                Strings.toString(traitAndLevel[partsOrder[FLAGSHIP_PART.HEALTH]]),
                '"},'
            )
        );
        parts = string(
            abi.encodePacked(
                parts,
                '{ "trait_type" : "CANNON LEVEL", "value" : "',
                Strings.toString(traitAndLevel[partsOrder[FLAGSHIP_PART.CANNON]]),
                '"},'
            )
        );
        parts = string(
            abi.encodePacked(
                parts,
                '{ "trait_type" : "HULL LEVEL", "value" : "',
                Strings.toString(traitAndLevel[partsOrder[FLAGSHIP_PART.HULL]]),
                '"},'
            )
        );
        parts = string(
            abi.encodePacked(
                parts,
                '{ "trait_type" : "SAILS LEVEL", "value" : "',
                Strings.toString(traitAndLevel[partsOrder[FLAGSHIP_PART.SAILS]]),
                '"},'
            )
        );
        parts = string(
            abi.encodePacked(
                parts,
                '{ "trait_type" : "HELM LEVEL", "value" : "',
                Strings.toString(traitAndLevel[partsOrder[FLAGSHIP_PART.HELM]]),
                '"},'
            )
        );
        parts = string(
            abi.encodePacked(
                parts,
                '{ "trait_type" : "FLAG LEVEL", "value" : "',
                Strings.toString(traitAndLevel[partsOrder[FLAGSHIP_PART.FLAG]]),
                '"},'
            )
        );
        parts = string(
            abi.encodePacked(
                parts,
                '{ "trait_type" : "FIGUREHEAD LEVEL", "value" : "',
                Strings.toString(traitAndLevel[partsOrder[FLAGSHIP_PART.FIGUREHEAD]]),
                '"}'
            )
        );
        string memory tokenName = string(abi.encodePacked("DPS Flagship #", Strings.toString(_tokenId)));
        return
            string(
                abi.encodePacked(
                    '{ "external_url": "',
                    baseUri,
                    '", "image": "',
                    baseUri,
                    '", "name": "',
                    tokenName,
                    '", "attributes": [',
                    parts,
                    "] }"
                )
            );
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlEnumerable, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

