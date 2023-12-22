// SPDX-License-Identifier: MIT
// Creator: base64.tech
pragma solidity ^0.8.13;

import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ECDSAUpgradeable.sol";
import "./ERC721EnumerableUpgradeable.sol";
import "./StringsUpgradeable.sol";
import "./SamuRiseLandErrors.sol";

import "./Base64.sol";

import "./console.sol";

interface ISamuRiseLand {
    function tokenIdToRarity(uint256 _tokenId) external view returns (uint256);
}

contract SamuRiseLandMetadataState is OwnableUpgradeable, UUPSUpgradeable {
    using StringsUpgradeable for uint256;

    enum DojoRarity{ YELLOW, ORANGE, BLUE, PURPLE, GREEN, RED, BROWN, BLACK }
    enum Faction { THRONE_OF_BLOOD, SWORD_OF_DOOM, HIDDEN_FORTRESS }
    enum ThroneOfBloodProvince { ECHIZEN, WAKASA, TAMBA }
    enum SwordOfDoomProvince { YAMATO, SETTSU, KII}
    enum HiddenFortressProvince { OMI, MINO, ISE }

    string [] factionNames; 
    string [] throneOfBloodProvinceNames;
    string [] swordOfDoomProvinceNames;
    string [] hiddenFortressProvinceNames;
    string [] dojoRarityNames;

    struct FactionMetadata {
        string faction;
        string province;
    }
    mapping(uint256 => FactionMetadata) public tokenIdToFactionMetadata;

    mapping(Faction => string[]) public factionToProvince;
    mapping(uint256 => uint256) public tokenIdToDojoLeveledUpAmount;
    mapping(uint256 => string) public landTokenIdToFaction;
    mapping(uint256 => string) public landTokenIdToProvince;
    mapping(address => bool) contractAddressToIsWhiteListed;

    string baseImageURL;
    address public sashimonoContract;
    address public landContract;

    bool private initialized;

    event TokenMetadataUpdated(uint256 tokenId);

    function initialize() public initializer {
        require(!initialized, "Contract instance has already been initialized");
        initialized = true;
        __Ownable_init_unchained();
        __UUPSUpgradeable_init_unchained();

        factionNames = ["THRONE_OF_BLOOD", "SWORD_OF_DOOM", "HIDDEN_FORTRESS"]; 
        throneOfBloodProvinceNames = [ "ECHIZEN", "WAKASA", "TAMBA" ];
        swordOfDoomProvinceNames = [ "YAMATO", "SETTSU", "KII"];
        hiddenFortressProvinceNames = [ "OMI", "MINO", "ISE" ];
        dojoRarityNames = ["YELLOW", "ORANGE", "BLUE", "PURPLE", "GREEN", "RED", "BROWN", "BLACK"];
        
        factionToProvince[Faction.THRONE_OF_BLOOD] = throneOfBloodProvinceNames;
        factionToProvince[Faction.SWORD_OF_DOOM] = swordOfDoomProvinceNames;
        factionToProvince[Faction.HIDDEN_FORTRESS] = hiddenFortressProvinceNames;

    }

    modifier callerIsWhitelistedContractOrOwner() {
        require(contractAddressToIsWhiteListed[msg.sender] || msg.sender == owner(), "caller is not whitelisted or owner");
        _;
    }


    function increaseTokenIdToDojoRarityBonus(uint256 _tokenId, uint256 _bonusAmount) 
        public 
        callerIsWhitelistedContractOrOwner()
    { 
        if (tokenIdToDojoLeveledUpAmount[_tokenId] + _bonusAmount <= uint256(DojoRarity.BROWN)){
            tokenIdToDojoLeveledUpAmount[_tokenId] += _bonusAmount;
            emit TokenMetadataUpdated(_tokenId);
        }
    }
    
    function setLandTokenIdFactionAndProvince(uint256 _tokenId, uint256 _faction, uint256 _province) 
        public 
        callerIsWhitelistedContractOrOwner()
    {
        emit TokenMetadataUpdated(_tokenId); 

        landTokenIdToFaction[_tokenId] = factionNames[_faction];
        landTokenIdToProvince[_tokenId] = factionToProvince[Faction(_faction)][_province];
        FactionMetadata memory factionMetadata = FactionMetadata(factionNames[_faction], factionToProvince[Faction(_faction)][_province]);
        tokenIdToFactionMetadata[_tokenId] = factionMetadata;
    }

    function getDojoRarity(uint256 _tokenId) public  view returns (string memory) {
        return dojoRarityNames[ISamuRiseLand(landContract).tokenIdToRarity(_tokenId) + tokenIdToDojoLeveledUpAmount[_tokenId]];
    }

    function getTraitsMetadata(uint256 _tokenId) public view returns (bytes memory) {
        return abi.encodePacked('"attributes":[{"trait_type":"Dojo","value":"',
                            getDojoRarity(_tokenId),
                            '"}, {"trait_type":"Faction","value":"',
                            landTokenIdToFaction[_tokenId],
                            '"}, {"trait_type":"Province","value":"',
                            landTokenIdToProvince[_tokenId],
                            '"}],');
    }


    function getMetadata(uint256 _tokenId) public view returns (string memory) {
        bytes memory factionMetadata;

        if (bytes(landTokenIdToFaction[_tokenId]).length > 0) {
            factionMetadata = abi.encodePacked(', {"trait_type":"Faction","value":"',
                                                landTokenIdToFaction[_tokenId],
                                                '"}, {"trait_type":"Province","value":"',
                                                landTokenIdToProvince[_tokenId],
                                                '"}');

        } 

        bytes memory metadata = abi.encodePacked(
                        '{"name":"Tengoku Land #',
                        _tokenId.toString(),
                        '","description":"The Samurai have arisen from the Bogai to find Tengoku desecrated and defiled. Now all 10,020 SamuRise must work together to purify their homeland and restore the honor their land once enjoyed.","attributes":[{"trait_type":"Dojo","value":"',
                        getDojoRarity(_tokenId),
                        '"}',
                        factionMetadata,
                        '],'
                    );
        metadata = abi.encodePacked(
                        metadata,
                        ' "image": "',
                        baseImageURL,
                        'dojo-',
                        getDojoRarity(_tokenId),
                        '/faction-',
                        landTokenIdToFaction[_tokenId],
                        '/province-',
                        landTokenIdToProvince[_tokenId],
                        '/land.gif"}'
                    );

          return Base64.encode(metadata);
    }


    /* owner functions */
    function addAddressToWhiteList(address _address) public onlyOwner {
        contractAddressToIsWhiteListed[_address] = true;
    }
    
    function setLandContract(address _address) public onlyOwner {
        landContract = _address;

    }

    function setBaseImageURL(string memory _url) public onlyOwner {
        baseImageURL = _url;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}



