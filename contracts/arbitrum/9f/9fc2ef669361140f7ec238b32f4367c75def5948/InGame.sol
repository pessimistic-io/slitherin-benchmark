// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./IERC20Upgradeable.sol";
import "./IPeekABoo.sol";
import "./ITraits.sol";
import "./ILevel.sol";
import "./IInGame.sol";
import "./InGameBase.sol";

contract InGame is Initializable,
    IInGame,
    OwnableUpgradeable,
    PausableUpgradeable,
    InGameBase {

    function initialize(
        IPeekABoo _peekaboo,
        ITraits _traits,
        ILevel _level,
        address _boo,
        address _magic
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        peekaboo = _peekaboo;
        traits = _traits;
        level = _level;
        boo = IERC20Upgradeable(_boo);
        magic = IERC20Upgradeable(_magic);
        traitPriceRate = 15 ether;
        abilityPriceRate = 30 ether;
    }



    modifier onlyPeekABoo() {
        require(
            _msgSender() == address(peekaboo),
            "Must be IPeekABoo.sol, don't cheat"
        );
        _;
    }

    function buyTraits(
        uint256 tokenId,
        uint256[] calldata traitTypes,
        uint256[] calldata traitIds,
        uint256 amount
    ) external {
        require(
            _msgSender() == peekaboo.ownerOf(tokenId),
            "ITraits can only be purchased by owner"
        );
        require(
            traitTypes.length == traitIds.length,
            "traitTypes and traitIds lengths are different"
        );
        uint256 totalBOO = 0;
        bool _isGhost = peekaboo.getTokenTraits(tokenId).isGhost;
        if (_isGhost == true) {
            for (uint256 i = 0; i < traitIds.length; i++) {
                require(
                    traitIds[i] <=
                        level.getUnlockedTraits(tokenId, traitTypes[i]),
                    "Trait not unlocked yet"
                );
                if (traitIds[i] <= traits.getRarityIndex(0, traitTypes[i], 1)) {
                    totalBOO += traitPriceRate;
                    boughtTraitCount[tokenId][1] =
                        boughtTraitCount[tokenId][1] +
                        1;
                } else if (
                    traitIds[i] <= traits.getRarityIndex(0, traitTypes[i], 2)
                ) {
                    totalBOO += (traitPriceRate * 2);
                    boughtTraitCount[tokenId][2] =
                        boughtTraitCount[tokenId][2] +
                        1;
                } else if (
                    traitIds[i] <= traits.getRarityIndex(0, traitTypes[i], 3)
                ) {
                    totalBOO += (traitPriceRate * 3);
                    boughtTraitCount[tokenId][3] =
                        boughtTraitCount[tokenId][3] +
                        1;
                }
                boughtTraits[tokenId][traitTypes[i]][traitIds[i]] = true;
            }
        } else {
            for (uint256 i = 0; i < traitIds.length; i++) {
                require(
                    traitIds[i] <=
                        level.getUnlockedTraits(tokenId, traitTypes[i]),
                    "Trait not unlocked yet"
                );
                if (traitIds[i] <= traits.getRarityIndex(1, traitTypes[i], 1)) {
                    totalBOO += traitPriceRate;
                    boughtTraitCount[tokenId][1] =
                        boughtTraitCount[tokenId][1] +
                        1;
                } else if (
                    traitIds[i] <= traits.getRarityIndex(1, traitTypes[i], 2)
                ) {
                    totalBOO += (traitPriceRate * 2);
                    boughtTraitCount[tokenId][2] =
                        boughtTraitCount[tokenId][2] +
                        1;
                } else if (
                    traitIds[i] <= traits.getRarityIndex(1, traitTypes[i], 3)
                ) {
                    totalBOO += (traitPriceRate * 3);
                    boughtTraitCount[tokenId][3] =
                        boughtTraitCount[tokenId][3] +
                        1;
                }
                boughtTraits[tokenId][traitTypes[i]][traitIds[i]] = true;
            }
        }
        require(amount >= totalBOO, "Not enough $BOO");
        _approveFor(msg.sender, boo, amount);
        boo.transferFrom(msg.sender, address(this), amount);
    }

    function buyAbilities(
        uint256 tokenId,
        uint256[] calldata abilities,
        uint256 amount
    ) external {
        require(
            _msgSender() == peekaboo.ownerOf(tokenId),
            "Only owner can buy abilities"
        );
        uint256 totalMAGIC = 0;
        uint256 _tier = peekaboo.getTokenTraits(tokenId).tier;
        require(
            peekaboo.getTokenTraits(tokenId).isGhost == false,
            "Only busters can buy abilities"
        );
        for (uint256 i = 0; i < abilities.length; i++) {
            if (abilities[i] == 0) {
                require(
                    _tier >= 1,
                    "This ability cannot be bought yet at this tier"
                );
                if (_tier < 2)
                    require(
                        boughtAbilities[tokenId][1] == false,
                        "This ability cannot be bought yet at this tier"
                    );
                totalMAGIC += abilityPriceRate;
                boughtAbilities[tokenId][0] = true;
            } else if (abilities[i] == 1) {
                require(
                    _tier >= 1,
                    "This ability cannot be bought yet at this tier"
                );
                if (_tier < 2)
                    require(
                        boughtAbilities[tokenId][0] == false,
                        "This ability cannot be bought yet at this level"
                    );
                totalMAGIC += abilityPriceRate;
                boughtAbilities[tokenId][1] = true;
            } else if (abilities[i] == 2) {
                require(
                    _tier >= 3,
                    "This ability cannot be bought yet at this tier"
                );
                if (_tier == 3)
                    require(
                        boughtAbilities[tokenId][3] == false &&
                            boughtAbilities[tokenId][4] == false,
                        "This ability cannot be bought yet at this level"
                    );
                if (_tier == 4)
                    require(
                        boughtAbilities[tokenId][3] == false ||
                            boughtAbilities[tokenId][4] == false,
                        "This ability cannot be bought yet at this level"
                    );
                totalMAGIC += abilityPriceRate * 2;
                boughtAbilities[tokenId][2] = true;
            } else if (abilities[i] == 3) {
                require(
                    _tier >= 3,
                    "This ability cannot be bought yet at this tier"
                );
                if (_tier == 3)
                    require(
                        boughtAbilities[tokenId][2] == false &&
                            boughtAbilities[tokenId][4] == false,
                        "This ability cannot be bought yet at this level"
                    );
                if (_tier == 4)
                    require(
                        boughtAbilities[tokenId][2] == false ||
                            boughtAbilities[tokenId][4] == false,
                        "This ability cannot be bought yet at this level"
                    );
                totalMAGIC += abilityPriceRate * 2;
                boughtAbilities[tokenId][3] = true;
            } else if (abilities[i] == 4) {
                require(
                    _tier >= 3,
                    "This ability cannot be bought yet at this tier"
                );
                if (_tier == 3)
                    require(
                        boughtAbilities[tokenId][2] == false &&
                            boughtAbilities[tokenId][4] == false,
                        "This ability cannot be bought yet at this level"
                    );
                if (_tier == 4)
                    require(
                        boughtAbilities[tokenId][2] == false ||
                            boughtAbilities[tokenId][4] == false,
                        "This ability cannot be bought yet at this level"
                    );
                totalMAGIC += abilityPriceRate * 2;
                boughtAbilities[tokenId][4] = true;
            } else if (abilities[i] == 5) {
                require(
                    _tier >= 5,
                    "This ability cannot be bought yet at this tier"
                );
                totalMAGIC += abilityPriceRate * 3;
                boughtAbilities[tokenId][5] = true;
            }
        }
        require(amount >= totalMAGIC, "Not enough $MAGIC");
        _approveFor(msg.sender, magic, amount);
        magic.transferFrom(msg.sender, address(this), amount);
    }

    function tierUp(uint256 tokenId, uint64 toTier) external {
        require(
            _msgSender() == peekaboo.ownerOf(tokenId),
            "Only owner can tier up the token"
        );
        if (peekaboo.getTokenTraits(tokenId).tier == 0) {
            require(
                peekaboo.getTokenTraits(tokenId).level / 10 >= 1,
                "You cannot reach this tier yet"
            );
            if (peekaboo.getTokenTraits(tokenId).isGhost == true) {
                require(
                    boughtTraitCount[tokenId][1] >= 7,
                    "Not enough uncommon traits bought"
                );
            } else
                require(
                    boughtTraitCount[tokenId][1] >= 6,
                    "Not enough uncommon traits bought"
                );
        } else if (peekaboo.getTokenTraits(tokenId).tier == 1) {
            require(
                peekaboo.getTokenTraits(tokenId).level / 10 >= 2,
                "You cannot reach this tier yet"
            );
            if (peekaboo.getTokenTraits(tokenId).isGhost == true) {
                require(
                    boughtTraitCount[tokenId][1] >= 14,
                    "Not enough uncommon traits bought"
                );
            } else
                require(
                    boughtTraitCount[tokenId][1] >= 12,
                    "Not enough uncommon traits bought"
                );
        } else if (peekaboo.getTokenTraits(tokenId).tier == 2) {
            require(
                peekaboo.getTokenTraits(tokenId).level / 10 >= 3,
                "You cannot reach this tier yet"
            );
            if (peekaboo.getTokenTraits(tokenId).isGhost == true) {
                require(
                    boughtTraitCount[tokenId][2] >= 7,
                    "Not enough rare traits bought"
                );
            } else
                require(
                    boughtTraitCount[tokenId][2] >= 6,
                    "Not enough rare traits bought"
                );
        } else if (peekaboo.getTokenTraits(tokenId).tier == 3) {
            require(
                peekaboo.getTokenTraits(tokenId).level / 10 >= 4,
                "You cannot reach this tier yet"
            );
            if (peekaboo.getTokenTraits(tokenId).isGhost == true) {
                require(
                    boughtTraitCount[tokenId][2] >= 7,
                    "Not enough legendary traits bought"
                );
            } else
                require(
                    boughtTraitCount[tokenId][2] >= 6,
                    "Not enough legendary traits bought"
                );
        } else if (peekaboo.getTokenTraits(tokenId).tier == 4) {
            require(
                peekaboo.getTokenTraits(tokenId).level / 10 >= 5,
                "You cannot reach this tier yet"
            );
            uint256 _boughtTraits = boughtTraitCount[tokenId][1] +
                boughtTraitCount[tokenId][2] +
                boughtTraitCount[tokenId][2];
            if (peekaboo.getTokenTraits(tokenId).isGhost == true) {
                require(_boughtTraits >= 127, "Not enough traits bought");
            } else require(_boughtTraits >= 76, "Not enough traits bought");
        } else {
            return;
        }
        peekaboo.incrementTier(tokenId);
    }

    function getBoughtTraitCount(uint256 tokenId, uint256 rarity)
        external
        returns (uint256)
    {
        return boughtTraitCount[tokenId][rarity];
    }

    function isBoughtTrait(
        uint256 tokenId,
        uint256 traitType,
        uint256 traitId
    ) external returns (bool) {
        uint256 ghostOrBuster = (peekaboo.getTokenTraits(tokenId).isGhost ==
            true)
            ? 0
            : 1;
        uint256 commonIndex = traits.getRarityIndex(
            ghostOrBuster,
            traitType,
            0
        );
        if (traitId <= commonIndex) return true;
        return boughtTraits[tokenId][traitType][traitId];
    }

    function isBoughtAbility(uint256 tokenId, uint256 ability)
        external
        returns (bool)
    {
        return boughtAbilities[tokenId][ability];
    }

    function _approveFor(
        address owner,
        IERC20Upgradeable token,
        uint256 amount
    ) internal {
        token.approve(address(this), amount);
    }

    function setBOO(address _boo) external onlyOwner {
        boo = IERC20Upgradeable(_boo);
    }

    function setMagic(address _magic) external onlyOwner {
        magic = IERC20Upgradeable(_magic);
    }

    function setPeekABoo(address _pab) external onlyOwner {
        peekaboo = IPeekABoo(_pab);
    }

    function setTraits(address _traits) external onlyOwner {
        traits = ITraits(_traits);
    }

    function setLevel(address _level) external onlyOwner {
        level = ILevel(_level);
    }

    function setTraitPriceRate(uint256 rate) external onlyOwner {
        traitPriceRate = rate;
    }

    function setAbilityPriceRate(uint256 rate) external onlyOwner {
        abilityPriceRate = rate;
    }
}

