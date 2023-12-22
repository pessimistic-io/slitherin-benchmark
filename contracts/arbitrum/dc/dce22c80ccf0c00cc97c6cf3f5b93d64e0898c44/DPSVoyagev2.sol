//SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721Enumerable.sol";
import "./AccessControlEnumerable.sol";
import "./IERC721.sol";
import "./IERC1155.sol";
import "./SafeERC20.sol";
import "./DPSStructs.sol";

contract DPSVoyageV2 is ERC721Enumerable, AccessControlEnumerable {
    using SafeERC20 for IERC20;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");
    bytes32 public constant UPGRADE_ROLE = keccak256("UPGRADE_ROLE");

    mapping(uint256 => VoyageConfigV2) configPerTokenId;

    bool mintingStopped = false;

    string private baseUri = "https://damnedpiratessociety.io/api/tokens/";

    uint256 public maxMintedId;

    event LockedUrl();
    event UrlChanged(uint256 indexed _id, string newUrl);
    event TokenRecovered(address indexed _token, address _destination, uint256 _amount);

    constructor() ERC721("DSP Voyage", "DSPVoyage") {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(UPGRADE_ROLE, _msgSender());
    }

    /**
     * @notice minting a new voyage with a config.
     * @param _owner the receiver of the voyage
     * @param _tokenId the id of the new voyage
     * @param _config the config for this voyage
     */
    function mint(
        address _owner,
        uint256 _tokenId,
        VoyageConfigV2 calldata _config
    ) external {
        require(_tokenId > 0, "Voyage Id 0 can not be minted");
        require(hasRole(MINTER_ROLE, _msgSender()), "Does not have role MINTER_ROLE");
        require(!mintingStopped, "Minting has been stopped");
        configPerTokenId[_tokenId] = _config;
        if (_tokenId > maxMintedId) maxMintedId = _tokenId;
        super._safeMint(_owner, _tokenId);
    }

    function burn(uint256 _tokenId) external {
        require(hasRole(BURNER_ROLE, _msgSender()), "Does not have role BURNER_ROLE");
        delete configPerTokenId[_tokenId];
        _burn(_tokenId);
    }

    function changeMinting(bool _stopped) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Does not have role DEFAULT_ADMIN_ROLE");
        mintingStopped = _stopped;
    }

    function getVoyageConfig(uint256 _voyageId) external view returns (VoyageConfigV2 memory config) {
        return configPerTokenId[_voyageId];
    }

    function exists(uint256 _tokenId) public view returns (bool) {
        return _exists(_tokenId);
    }

    function setBaseUri(string memory _newBaseUri) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "Does not have role DEFAULT_ADMIN_ROLE ");
        baseUri = _newBaseUri;
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

        string memory traits;
        VoyageConfigV2 memory config = configPerTokenId[_tokenId];

        traits = string(
            abi.encodePacked(
                traits,
                '{ "trait_type" : "TYPE", "value" : "',
                Strings.toString(config.typeOfVoyage),
                '"},'
            )
        );
        traits = string(
            abi.encodePacked(
                traits,
                '{ "trait_type" : "NUMBER OF INTERACTIONS", "value" : "',
                Strings.toString(config.noOfInteractions),
                '"},'
            )
        );
        traits = string(
            abi.encodePacked(
                traits,
                '{ "trait_type" : "LENGTH OF VOYAGE", "value" : "',
                Strings.toString(config.noOfInteractions * config.gapBetweenInteractions),
                '"},'
            )
        );
        traits = string(
            abi.encodePacked(
                traits,
                '{ "trait_type" : "GAP BETWEEN INTERACTIONS", "value" : "',
                Strings.toString(config.gapBetweenInteractions),
                '"}'
            )
        );

        string memory tokenName = string(abi.encodePacked("DPS VOYAGE #", Strings.toString(_tokenId)));
        string memory tokenUrl = string(abi.encodePacked(baseUri, Strings.toString(uint8(config.typeOfVoyage)), ".png"));
        return
            string(
                abi.encodePacked(
                    '{ "external_url": "',
                    tokenUrl,
                    '", "image": "',
                    tokenUrl,
                    '", "name": "',
                    tokenName,
                    '", "attributes": [',
                    traits,
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

    /**
     * @notice Recover NFT sent by mistake to the contract
     * @param _nft the NFT address
     * @param _destination where to send the NFT
     * @param _tokenId the token to want to recover
     */
    function recoverNFT(
        address _nft,
        address _destination,
        uint256 _tokenId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_destination != address(0), "Destination can not be address 0");
        IERC721(_nft).safeTransferFrom(address(this), _destination, _tokenId);
        emit TokenRecovered(_nft, _destination, _tokenId);
    }

    /**
     * @notice Recover NFT sent by mistake to the contract
     * @param _nft the 1155 NFT address
     * @param _destination where to send the NFT
     * @param _tokenId the token to want to recover
     * @param _amount amount of this token to want to recover
     */
    function recover1155NFT(
        address _nft,
        address _destination,
        uint256 _tokenId,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_destination != address(0), "Destination can not be address 0");
        IERC1155(_nft).safeTransferFrom(address(this), _destination, _tokenId, _amount, "");
        emit TokenRecovered(_nft, _destination, _tokenId);
    }

    /**
     * @notice Recover TOKENS sent by mistake to the contract
     * @param _token the TOKEN address
     * @param _destination where to send the NFT
     */
    function recoverERC20(address _token, address _destination) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_destination != address(0), "Destination can not be address 0");
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(_destination, amount);
        emit TokenRecovered(_token, _destination, amount);
    }
}

