// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./Base64.sol";
import "./Strings.sol";
import "./Ownable.sol";
import "./ECDSA.sol";

import "./ITroveStreetPunksStaking.sol";
import "./ITroveStreetPunksBreeding.sol";


contract TroveStreetPunksMetadata is Ownable {

    using Strings for uint256;
    using ECDSA for bytes32;

    address public constant SIGNER_ADDRESS = 0xf77f5B4921547f34B37dC7675E978F0cac1A8211;

    address public stakingAddress;
    address public breedingAddress; 

    string private name;
    string private description;
    string private baseTokenURI;

    mapping(uint256 => uint256) private tokenToDna;
    mapping(uint256 => string) private attributeToValue;
    mapping(uint256 => mapping(uint256 => string)) private traitToValues;

    constructor(
        string memory _name,
        string memory _description,
        string memory _baseTokenURI
    ) {
        name = _name;
        description = _description;
        baseTokenURI = _baseTokenURI;
    }

    function setName(string memory _string) external onlyOwner {
        name = _string;
    }

    function setDescription(string memory _string) external onlyOwner {
        description = _string;
    }

    function setBaseTokenURI(string memory _string) external onlyOwner {
        baseTokenURI = _string;
    }

    function setStakingAddress(address _address) external onlyOwner {
        stakingAddress = _address;
    }

    function setBreedingAddress(address _address) external onlyOwner {
        breedingAddress = _address;
    }

    function setAttributeValue(uint256 _attribute, string memory _value) external onlyOwner {
        attributeToValue[_attribute] = _value;
    }

    function setAttributeValues(string[] memory _values) external onlyOwner {
        uint256 length = _values.length;

        for (uint256 i; i < length; i ++) {
            attributeToValue[i] = _values[i];
        }
    }

    function setTraitValue(uint256 _trait, uint256 _index, string memory _value) external onlyOwner {
        traitToValues[_trait][_index] = _value;
    }

    function setTraitValues(uint256 _trait, string[] memory _values) external onlyOwner {
        uint256 length = _values.length;

        for (uint256 i; i < length; i ++) {
            traitToValues[_trait][i] = _values[i];
        }
    }

    function supplyDna(uint256 _tokenId, uint256 _dna, bytes memory _signature) external {
        require(!exists(_tokenId), "DNA already supplied");
        require(_verify(abi.encodePacked(_tokenId, _dna), _signature), "Invalid signature");

        tokenToDna[_tokenId] = _dna;
    }

    function metadataOf(uint256 _tokenId) external view returns (string memory) {
        uint256 dna = tokenToDna[_tokenId];

        if (dna == 0) 
            return "";

        string memory tokenId = _tokenId.toString();

        string memory json = '{\n';

        json = string(
            abi.encodePacked(
                json,
                '  "name": "',
                name,
                tokenId,
                '",\n'
            )
        );

        json = string(
            abi.encodePacked(
                json,
                '  "image": "',
                baseTokenURI,
                tokenId,
                '.png",\n'
            )
        );

        json = string(
            abi.encodePacked(
                json,
                '  "description": "',
                description,
                '",\n'
            )
        );

        json = string(
            abi.encodePacked(
                json,
                '  "attributes": ',
                _attributes(_tokenId, dna),
                '}'
            )
        );
        
        json = Base64.encode(
            bytes(
                json
            )
        );

        json = string(
            abi.encodePacked(
                'data:application/json;base64,',
                json
            )
        );

        return json;
    }

    function traitsOf(uint256 _tokenId) external view returns (uint256[] memory) {
        uint256 dna = dnaOf(_tokenId);
        return _dnaToTraits(dna);
    }

    function dnaOf(uint256 _tokenId) public view returns (uint256) {
        uint256 dna = tokenToDna[_tokenId];
        require(dna != 0, "DNA not supplied");
        return dna;
    }

    function exists(uint256 _tokenId) public view returns (bool) {
        return tokenToDna[_tokenId] != 0;
    }

    function _verify(bytes memory _data, bytes memory _signature) internal pure returns (bool) {
        return keccak256(_data)
            .toEthSignedMessageHash()
            .recover(_signature) == SIGNER_ADDRESS;
    }

    function _dnaToTraits(uint256 _dna) internal pure returns (uint256[] memory) {
        uint256[] memory traits = new uint256[](11);
        uint256 shift;

        for (uint256 i; i < 11; i ++) {
            traits[i] = (_dna & (255 << shift)) >> shift;
            shift += 8; 
        }

        return traits;
    }

    function _attributes(uint256 _tokenId, uint256 _dna) internal view returns (string memory) {
        uint256[] memory traits = _dnaToTraits(_dna);
        string memory attributes = '[\n';

        for (uint256 i; i < 13; i ++) {
            string memory value;
            uint256 index = i;

            if (i < 11) {

                if (i == 4) {

                    if (traits[2] > 0)
                        index = 11; 

                } else if (i == 8) {

                    uint256 skin = traits[1];

                    bool one = traits[2] > 0 && skin != 3 && skin != 4;
                    bool no = skin == 1 || skin == 2;

                    if (one || no)
                        index = 12;


                } else if (i == 9) {

                    if (traits[2] > 0)
                        index = 13; 

                }

                value = traitToValues[index][traits[i]];

            } else if (i == 11) {

                value = stakingAddress != address(0) && ITroveStreetPunksStaking(stakingAddress).breedable(_tokenId) ? "Ready" : "Unready";

            } else {

                value = "0/2";

                if (breedingAddress != address(0)) {

                    value = string(
                        abi.encodePacked(
                            ITroveStreetPunksBreeding(breedingAddress).kids(_tokenId).toString(),
                            '/',
                            ITroveStreetPunksBreeding(breedingAddress).maxKids(_tokenId).toString()
                        )
                    );

                }

            }

            attributes = string(
                abi.encodePacked(
                    attributes,
                    '    {\n      "trait_type": "',
                    attributeToValue[i],
                    '",\n      "value": "',
                    value,
                    '"\n    }',
                    i == 12 ? '' : ',',
                    '\n'
                )
            );
        }

        return string(
            abi.encodePacked(
                attributes,
                '  ]\n'
            )
        );
    }

}
