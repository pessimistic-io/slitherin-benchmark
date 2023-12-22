// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./base64.sol";
import "./Strings.sol";
import "./IUserNFTDescriptor.sol";
import "./IUserManager.sol";
import "./Gameable.sol";

abstract contract BaseNFTUserDescriptor is IUserNFTDescriptor {
    function tokenURI(
        address hub,
        uint256 userId
    ) external view override returns (string memory) {
        IUserManager.UserDescription memory _userDescription = IUserManager(hub)
            .getUserDescription(userId);
        return _constructTokenURI(_userDescription);
    }

    function _constructTokenURI(
        IUserManager.UserDescription memory _userDescription
    ) private pure returns (string memory) {
        string memory _name = _generateName(_userDescription);
        string memory _description = _generateDescription();
        string memory _image = Base64.encode(
            bytes(_generateSVG(_userDescription))
        );
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                _name,
                                '", "description":"',
                                _description,
                                '", "image": "data:image/svg+xml;base64,',
                                _image,
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    function _generateDescription() private pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "This collection contains all the heroes who participated in the Bored In Borderland Season 1.\\n\\n",
                    "Whether they are dead or alive, they are the pioneers of the game and all players who participated in Season 1 will receive benefits for future seasons.\\n\\n",
                    "Each NFT contains the name of the hero, the score represented by the amount of xBCOIN accumulated by the NFT and the current APR of the Hero."
                )
            );
    }

    function _getHeroCategory() internal pure virtual returns (string memory);

    function _generateName(
        IUserManager.UserDescription memory _userDescription
    ) private pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "Heroes of Borderland Season 1 - ",
                    _getHeroCategory(),
                    " - #",
                    Strings.toString(_userDescription.userId)
                )
            );
    }

    function _generateSVG(
        IUserManager.UserDescription memory _userDescription
    ) private pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    _generateSVGMeta(),
                    _generateStyleDefs(),
                    _generateSVGCalques(),
                    _generateSVGForm(),
                    _generateSVGDesign(),
                    _generateSVGData(_userDescription),
                    "</g></g></svg>"
                )
            );
    }

    function _generateSVGDesign() internal pure virtual returns (string memory);

    function _generateSVGMeta() internal pure virtual returns (string memory);

    function _generateStyleDefs() internal pure virtual returns (string memory);

    function _generateSVGCalques() private pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    '<g id="Calque_1" data-name="Calque 1"><g id="Calque_2" data-name="Calque 2">'
                )
            );
    }

    function _generateSVGForm() internal pure virtual returns (string memory);

    function _generateSVGData(
        IUserManager.UserDescription memory _userDescription
    ) private pure returns (string memory) {
        uint256 _scoreRounded = (_userDescription.balance -
            (_userDescription.balance % 10 ** 18)) / 10 ** 18;
        uint256 _aprRounded = (_userDescription.apr -
            (_userDescription.apr % 10 ** 18) /
            10 ** 18) / 10000;
        string memory _apr = Strings.toString(_aprRounded);
        string memory _score = Strings.toString(_scoreRounded);
        return _getSVGData(_userDescription.userId, _score, _apr);
    }

    function _getSVGData(
        uint256 userID,
        string memory score,
        string memory apr
    ) internal pure virtual returns (string memory);
}

