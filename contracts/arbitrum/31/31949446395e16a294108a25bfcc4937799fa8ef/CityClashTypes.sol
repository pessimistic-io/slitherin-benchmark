//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.4;

interface CityClashTypes {
    struct City {
        string city;
        string country;
        uint256 points;
        uint8 cityFaction;        //1 red, 2 green, 3 blue
        uint256 lastTransferTime;
        string baseImageUrl;
        uint256 origPoints;
    }

    struct CityWithId {
        uint256 id;               //1 to 3000
        string city;
        string country;
        uint256 points;
        uint8 cityFaction;        //1 red, 2 green, 3 blue
    }

    struct CountryScore {
        uint256 red;
        uint256 green;
        uint256 blue;
    }

     struct CountryToScore {
        string country;
        uint256 red;
        uint256 green;
        uint256 blue;
    }

    struct AddressToFaction {
        address a;
        uint8 faction;
    }
}
