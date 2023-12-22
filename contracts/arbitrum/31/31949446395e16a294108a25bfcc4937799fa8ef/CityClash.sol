//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

import "./CityClashScore.sol";
import "./CityClashTowersInterface.sol";

contract CityClash is CityClashScore {

    event TransferEvent(uint256 tokenId);
    event UpgradeCityEvent(uint256 tokenId);
    event UpdateCityImageEvent(uint256 tokenId);

    function uploadMetadata(CityClashTypes.CityWithId[] memory _cities) external onlyOwner {
        require(idToCities[MAX_CITIES].cityFaction == 0 || idToCities[MAX_CITIES - FOUNDERS_RESERVE_AMOUNT].cityFaction == 0, "All cities already have metadata uploaded");
        for(uint i = 0; i < _cities.length; i++) {
            //if there is no metadata for this city already but it has been minted
            if(idToCities[_cities[i].id].points == 0 && _exists(_cities[i].id)) {
                idToCities[_cities[i].id] = CityClashTypes.City(_cities[i].city, _cities[i].country, _cities[i].points, _cities[i].cityFaction, 0, "", 0);
                addressToFaction[ownerOf(_cities[i].id)] = _cities[i].cityFaction;
            }
        }
    }

    function uploadScore(CityClashTypes.CountryToScore[] memory _countryToScore,
                        uint256 red,
                        uint256 green,
                        uint256 blue) external onlyOwner {
        for(uint i = 0; i < _countryToScore.length; i++) {
            countryToScore[_countryToScore[i].country] = CityClashTypes.CountryScore(_countryToScore[i].red, _countryToScore[i].green, _countryToScore[i].blue);
        }
        redScore = red;
        greenScore = green;
        blueScore = blue;
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        CityClashTypes.City storage city = idToCities[tokenId];
        if(!hasUploadedMetadata(city)) {
            super._transfer(from, to, tokenId);
            return;
        }
        
        //choose faction for new address
        bool isNewOwner = addressToFaction[to] == 0;
        uint8 faction;
        if(isNewOwner) {
            faction = getOverallLosingFaction();
        } else {
            faction = addressToFaction[to];
        }
        super._transfer(from, to, tokenId);
        //update our data after the transfer has succeeded
        addressToFaction[to] = faction;

        if(addressToFaction[from] != addressToFaction[to]) {
            //current winning faction
            CityClashTypes.CountryScore storage countryScore = countryToScore[city.country];
            uint8 winningFaction = getWinningFaction(countryScore.red, countryScore.green, countryScore.blue);

            //set current city to new faction
            city.cityFaction = faction;
            city.lastTransferTime = block.timestamp;
            if(addressToFaction[from] == 1) {
                countryScore.red -= city.points;
            } else if(addressToFaction[from] == 2) {
                countryScore.green -= city.points;
            } else if(addressToFaction[from] == 3) {
                countryScore.blue -= city.points;
            }
            if(faction == 1) {
                countryScore.red += city.points;
            } else if(faction == 2) {
                countryScore.green += city.points;
            } else if(faction == 3) {
                countryScore.blue += city.points;
            }
            uint256 countryPoints = countryScore.red + countryScore.green + countryScore.blue;
            updateFactionScore(countryPoints, winningFaction, city);
            
        }
        emit TransferEvent(tokenId);
    }

    function tokenURI(uint256 _tokenId) public view virtual override returns (string memory) {
        require(_exists(_tokenId), "ERC721Metadata: URI query for nonexistent token");
        CityClashTypes.City memory city = idToCities[_tokenId];
        console.log('tokenId', _tokenId);
        console.log('city', city.city);
        
        string memory attributes = string(
            abi.encodePacked(
                '{"trait_type": "City",',
                '"value": "', city.city,
                '"},{"trait_type": "Country",',
                '"value": "', city.country,
                '"},{"trait_type": "Points",',
                '"value": ', uintToByteString(city.points, 2),
                '},{"trait_type": "City Faction",',
                '"value": "', factionToColorName(city.cityFaction),
                '"},{"trait_type": "Country Faction",',
                '"value": "', factionToColorName(getCountryFaction(city.country)),
                '"}'
            )
        );
        if(!hasUploadedMetadata(city) || keccak256(abi.encodePacked(baseUrl)) == keccak256(abi.encodePacked(""))) {
            attributes = '';
        }

        string memory imageString = getImage(city);
        string memory nameString = city.city;
        if(!hasUploadedMetadata(city) || keccak256(abi.encodePacked(baseUrl)) == keccak256(abi.encodePacked(""))) {
            imageString = placeHolderImage;
            nameString = string(abi.encodePacked("City ", uintToByteString(_tokenId, 4)));
        }
        
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{',
                            '"name": "', nameString,
                            '", "tokenId": ', uintToByteString(_tokenId, 4),
                            ', "image": ', '"', imageString,
                            '", "description": "City Clash is a P2E, social strategy game where 3 factions compete by buying and selling NFTs based on real world cities. The game is built entirely on-chain, and is fully functional at mint time!",',
                            '"attributes": [',
                                attributes,
                            ']',
                        '}'
                    )
                )
            )
        );

        string memory finalTokenUri = string(abi.encodePacked("data:application/json;base64,", json));
        console.log("\n--------------------");
        console.log(finalTokenUri);
        console.log("--------------------\n");
        return finalTokenUri;
    }

    function getImage(CityClashTypes.City memory city) public view returns (string memory) {
        uint p = city.points;
        string memory cityBaseUrl = baseUrl;
        if(keccak256(abi.encodePacked(city.baseImageUrl)) != keccak256(abi.encodePacked("")) && keccak256(abi.encodePacked(city.baseImageUrl)) != keccak256(abi.encodePacked("upgraded"))) {
            cityBaseUrl = city.baseImageUrl;
        }
        if(city.origPoints != 0) {
            p = city.origPoints;
        }
        string memory imageBytes = toHex(
            keccak256(
                abi.encodePacked(
                    uintToByteString(p, 2),
                    city.city,
                    city.country
                )
            )
        );
        return string(
            abi.encodePacked(
                cityBaseUrl,
                "/",
                imageBytes,
                "_",
                uintToByteString(city.cityFaction, 1),
                "_",
                uintToByteString(getCountryFaction(city.country), 1),
                ".png"
            )
        );
    }

    function factionToColorName(uint _faction) private pure returns (string memory str) {
        if(_faction == 1) {
            return "red";
        } else if(_faction == 2) {
            return "green";
        } else if(_faction == 3) {
            return "blue";
        }
    }

    function upgradeCity(uint _tokenId, uint points, bool isPositive) external {
        require(isAddressAbleToUpgrade[msg.sender], "Only the upgrade Contract can call this function");

        CityClashTypes.City storage city = idToCities[_tokenId];

        //update the scores
        CityClashTypes.CountryScore storage countryScore = countryToScore[city.country];
        uint8 winningFaction = getWinningFaction(countryScore.red, countryScore.green, countryScore.blue);
        if(city.origPoints == 0) {
            city.origPoints = city.points;
        }
        if(isPositive) {
            city.points += points;
            if(city.cityFaction == 1) {
                countryScore.red += points;
            } else if(city.cityFaction == 2) {
                countryScore.green += points;
            } else if(city.cityFaction == 3) {
                countryScore.blue += points;
            }
            if(winningFaction == 1) {
                redScore += points;
            } else if(winningFaction == 2) {
                greenScore += points;
            } else if(winningFaction == 3) {
                blueScore += points;
            }
        } else {
            city.points -= points;
            if(city.cityFaction == 1) {
                countryScore.red -= points;
            } else if(city.cityFaction == 2) {
                countryScore.green -= points;
            } else if(city.cityFaction == 3) {
                countryScore.blue -= points;
            }
            if(winningFaction == 1) {
                redScore -= points;
            } else if(winningFaction == 2) {
                greenScore -= points;
            } else if(winningFaction == 3) {
                blueScore -= points;
            }
        }
        city.baseImageUrl = "upgraded";
        
        uint256 countryPoints = countryScore.red + countryScore.green + countryScore.blue;
        updateFactionScore(countryPoints, winningFaction, city);
        emit UpgradeCityEvent(_tokenId);
    }

    function updateCityImage(uint _tokenId, string memory _imageBaseUrl) external {
        require(isAddressAbleToUpgrade[msg.sender], "Only the upgrade Contract can call this function");
        CityClashTypes.City storage city = idToCities[_tokenId];
        city.baseImageUrl = _imageBaseUrl;
        emit UpdateCityImageEvent(_tokenId);
    }

    /*
    Convert uint to byte string, padding number string with spaces at end.
    Useful to ensure result's length is a multiple of 3, and therefore base64 encoding won't
    result in '=' padding chars.
    */
    function uintToByteString(uint _a, uint _fixedLen) internal pure returns (bytes memory _uintAsString) {
        uint j = _a;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(_fixedLen);
        j = _fixedLen;
        if (_a == 0) {
            bstr[0] = "0";
            len = 1;
        }
        while (j > len) {
            j = j - 1;
            bstr[j] = bytes1(' ');
        }
        uint k = len;
        while (_a != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_a - _a / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _a /= 10;
        }
        return bstr;
    }

    //https://leckylao.com/2022/02/03/solidity-bytes-to-string-and-bytes-to-string-as-output/
    function toHex16 (bytes16 data) internal pure returns (bytes32 result) {
        result = bytes32 (data) & 0xFFFFFFFFFFFFFFFF000000000000000000000000000000000000000000000000 |
            (bytes32 (data) & 0x0000000000000000FFFFFFFFFFFFFFFF00000000000000000000000000000000) >> 64;
        result = result & 0xFFFFFFFF000000000000000000000000FFFFFFFF000000000000000000000000 |
            (result & 0x00000000FFFFFFFF000000000000000000000000FFFFFFFF0000000000000000) >> 32;
        result = result & 0xFFFF000000000000FFFF000000000000FFFF000000000000FFFF000000000000 |
            (result & 0x0000FFFF000000000000FFFF000000000000FFFF000000000000FFFF00000000) >> 16;
        result = result & 0xFF000000FF000000FF000000FF000000FF000000FF000000FF000000FF000000 |
            (result & 0x00FF000000FF000000FF000000FF000000FF000000FF000000FF000000FF0000) >> 8;
        result = (result & 0xF000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000) >> 4 |
            (result & 0x0F000F000F000F000F000F000F000F000F000F000F000F000F000F000F000F00) >> 8;
        result = bytes32 (0x3030303030303030303030303030303030303030303030303030303030303030 +
            uint256 (result) +
            (uint256 (result) + 0x0606060606060606060606060606060606060606060606060606060606060606 >> 4 &
            0x0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F) * 7);
    }
    
    function toHex(bytes32 data) public pure returns (string memory) {
        return string (abi.encodePacked ("0x", toHex16 (bytes16 (data)), toHex16 (bytes16 (data << 128))));
    }

    function withdraw() external onlyOwner {
        uint balance = address(this).balance;
        uint share = balance / 14;
        (bool success1,) = address(0x9FFfd1CA952faD6BE57b99b61a0E75c192F201c1).call{value: share}('');
        (bool success2,) = address(0x2429Bc492d2cdfB7114963aF5C3f4d23922af27e).call{value: share}('');
        (bool success3,) = msg.sender.call{value: balance * 6 / 7}('');
        require(success1 && success2 && success3, "Withdrawal failed");
    }
}
