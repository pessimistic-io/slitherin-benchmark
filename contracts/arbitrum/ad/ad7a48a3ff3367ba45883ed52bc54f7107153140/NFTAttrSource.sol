// SPDX-License-Identifier: MIT
// Metaline Contracts (HeroNFTAttrSource.sol)

pragma solidity ^0.8.0;

import "./Context.sol";
import "./AccessControl.sol";

 /**
  * @dev hero nft miner attribute
  */
 struct HeroNFTMinerAttr {
     uint32 produceRate;
     uint32 minerRate;
     uint32 shopRate;
     uint16 sailerSpeedPer;
     uint16 sailerLoadPer;
     uint16 sailerRangePer;
     uint32 hashRate;
 }

 /**
  * @dev hero nft battle attribute
  */
 struct HeroNFTBattleAttr { 
     uint32 attack;
     uint32 defense;
     uint32 hitpoint;
     uint16 miss;
     uint16 doge;
     uint16 critical;
     uint16 decritical;
     uint16 speed;
 }
 
 /**
  * @dev ship nft miner attribute
  */
 struct ShipNFTMinerAttr {
    uint16 speed;
    uint32 maxLoad;
    uint32 maxRange;
    uint32 foodPerMile;
    uint8 maxSailer;
    uint32 hashRate;
    
    // TO DO : add attr
 }

 /**
  * @dev ship nft battle attribute
  */
 struct ShipNFTBattleAttr { 
    uint32 attack;
    uint32 defense;
    uint32 hitpoint;
    uint16 miss;
    uint16 doge;
    uint16 critical;
    uint16 decritical;
    uint16 speed;
    uint8 maxSailer;

    // TO DO : add attr
 }

/**
 * @dev nft attribute source contract
 */
contract NFTAttrSource_V1 is
    Context,
    AccessControl
{
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    mapping(uint32=>HeroNFTMinerAttr) public _heroMineAttrs;
    mapping(uint32=>HeroNFTBattleAttr) public _heroBattleAttrs;

    mapping(uint32=>ShipNFTMinerAttr) public _shipMineAttrs;
    mapping(uint32=>ShipNFTBattleAttr) public _shipBattleAttrs;

    uint16 public _heroMineFactor;
    uint16 public _heroBattleFactor;
    uint16 public _shipMineFactor;
    uint16 public _shipBattleFactor;

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MANAGER_ROLE, _msgSender());
    }

    // attr = attr * (1 + factor / 10000) 
    function setLevelUpFactor(
        uint16 heroMineFactor, 
        uint16 heroBattleFactor, 
        uint16 shipMineFactor, 
        uint16 shipBattleFactor
    ) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "NFTAttrSource_V1: must have manager role to manage");

        _heroMineFactor = heroMineFactor;
        _heroBattleFactor = heroBattleFactor;
        _shipMineFactor = shipMineFactor;
        _shipBattleFactor = shipBattleFactor;

    }

    /**
    * @dev get hero or pet miner attribute by mineAttr
    * @param mineAttr miner attribtue id
    * @param starLevel hero star level, if nft is pet, startLevel always = 1
    * @return data output data of HeroNFTMinerAttr
    */
    function getHeroMinerAttr(uint32 mineAttr, uint16 starLevel) external view returns (HeroNFTMinerAttr memory data)
    {
        data = _heroMineAttrs[mineAttr];
        data.produceRate = uint32(data.produceRate + uint64(data.produceRate) * starLevel * _heroMineFactor / 10000);
        data.minerRate = uint32(data.minerRate + uint64(data.minerRate) * starLevel * _heroMineFactor / 10000);
        data.shopRate = uint32(data.shopRate + uint64(data.shopRate) * starLevel * _heroMineFactor / 10000);
        data.sailerSpeedPer = uint16(data.sailerSpeedPer + uint64(data.sailerSpeedPer) * starLevel * _heroMineFactor / 10000);
        data.sailerLoadPer = uint16(data.sailerLoadPer + uint64(data.sailerLoadPer) * starLevel * _heroMineFactor / 10000);
        data.sailerRangePer = uint16(data.sailerRangePer + uint64(data.sailerRangePer) * starLevel * _heroMineFactor / 10000);
        data.hashRate = uint32(data.hashRate + uint64(data.hashRate) * starLevel * _heroMineFactor / 10000);
    }

    /**
    * @dev get hero or pet battle attribute by battleAttr
    * @param battleAttr battle attribtue id
    * @param level hero or pet nft level
    * @return data output data of HeroNFTBattleAttr
    */
    function getHeroBattleAttr(uint32 battleAttr, uint16 level) external view returns (HeroNFTBattleAttr memory data)
    {
        data = _heroBattleAttrs[battleAttr];
        data.attack = uint32(data.attack + uint64(data.attack) * level * _heroBattleFactor / 10000);
        data.defense = uint32(data.defense + uint64(data.defense) * level * _heroBattleFactor / 10000);
        data.hitpoint = uint32(data.hitpoint + uint64(data.hitpoint) * level * _heroBattleFactor / 10000);
        data.miss = uint16(data.miss + uint64(data.miss * level) * _heroBattleFactor / 10000);
        data.doge = uint16(data.doge + uint64(data.doge * level) * _heroBattleFactor / 10000);
        data.critical = uint16(data.critical + uint64(data.critical) * level * _heroBattleFactor / 10000);
        data.decritical = uint16(data.decritical + uint64(data.decritical) * level * _heroBattleFactor / 10000);
        data.speed = uint16(data.speed + uint64(data.speed) * level * _heroBattleFactor / 10000);
    }

    /**
    * @dev set hero or pet miner attributes
    * @param mineAttrs mine attribute ids
    * @param datas input data array of HeroNFTMinerAttr
    */
    function setHeroMinerAttr(uint32[] memory mineAttrs, HeroNFTMinerAttr[] memory datas) external
    {
        require(mineAttrs.length == datas.length, "NFTAttrSource_V1: parameter error");
        require(hasRole(MANAGER_ROLE, _msgSender()), "NFTAttrSource_V1: must have manager role to manage");

        for(uint i=0; i< mineAttrs.length; ++i){
            _heroMineAttrs[mineAttrs[i]] = datas[i];
        }
    }

    /**
    * @dev set hero or pet battle attributes
    * @param battleAttrs battle attribute ids
    * @param datas input data array of HeroNFTBattleAttr
    */
    function setHeroBattleAttr(uint32[] memory battleAttrs, HeroNFTBattleAttr[] memory datas) external
    {
        require(battleAttrs.length == datas.length, "NFTAttrSource_V1: parameter error");
        require(hasRole(MANAGER_ROLE, _msgSender()), "NFTAttrSource_V1: must have manager role to manage");

        for(uint i=0; i< battleAttrs.length; ++i){
            _heroBattleAttrs[battleAttrs[i]] = datas[i];
        }
    }
    
    /**
    * @dev get ship miner attribute by mineAttr
    * @param mineAttr miner attribtue id
    * @param level ship nft level
    * @return data output data of ShipNFTMinerAttr
    */
    function getShipMinerAttr(uint32 mineAttr, uint16 level) external view returns (ShipNFTMinerAttr memory data)
    {
        data = _shipMineAttrs[mineAttr];
        
        data.speed = uint16(data.speed + uint64(data.speed) * level * _shipMineFactor / 10000);
        data.maxLoad = uint32(data.maxLoad + uint64(data.maxLoad) * level * _shipMineFactor / 10000);
        data.maxRange = uint32(data.maxRange + uint64(data.maxRange) * level * _shipMineFactor / 10000);
        data.foodPerMile = uint32(data.foodPerMile + uint64(data.foodPerMile) * level * _shipMineFactor / 10000);
        data.maxSailer = uint8(data.maxSailer + uint64(data.maxSailer) * level * _shipMineFactor / 10000);
        data.hashRate = uint32(data.hashRate + uint64(data.hashRate) * level * _shipMineFactor / 10000);
    }

    /**
    * @dev get ship battle attribute by battleAttr
    * @param battleAttr battle attribtue id
    * @param level ship nft level
    * @return data output data of ShipNFTBattleAttr
    */
    function getShipBattleAttr(uint32 battleAttr, uint16 level) external view returns (ShipNFTBattleAttr memory data)
    {
        data = _shipBattleAttrs[battleAttr];
        data.attack = uint32(data.attack + uint64(data.attack) * level * _shipBattleFactor / 10000);
        data.defense = uint32(data.defense + uint64(data.defense) * level * _shipBattleFactor / 10000);
        data.hitpoint = uint32(data.hitpoint + uint64(data.hitpoint) * level * _shipBattleFactor / 10000);
        data.miss = uint16(data.miss + uint64(data.miss * level) * _shipBattleFactor / 10000);
        data.doge = uint16(data.doge + uint64(data.doge * level) * _shipBattleFactor / 10000);
        data.critical = uint16(data.critical + uint64(data.critical) * level * _shipBattleFactor / 10000);
        data.decritical = uint16(data.decritical + uint64(data.decritical) * level * _shipBattleFactor / 10000);
        data.speed = uint16(data.speed + uint64(data.speed) * level * _shipBattleFactor / 10000);
        data.maxSailer = uint8(data.maxSailer + uint64(data.maxSailer) * level * _shipBattleFactor / 10000);
    }

    /**
    * @dev set ship miner attributes
    * @param mineAttrs mine attribute ids
    * @param datas input data array of ShipNFTMinerAttr
    */
    function setShipMinerAttr(uint32[] memory mineAttrs, ShipNFTMinerAttr[] memory datas) external
    {
        require(mineAttrs.length == datas.length, "NFTAttrSource_V1: parameter error");
        require(hasRole(MANAGER_ROLE, _msgSender()), "NFTAttrSource_V1: must have manager role to manage");

        for(uint i=0; i< mineAttrs.length; ++i){
            _shipMineAttrs[mineAttrs[i]] = datas[i];
        }
    }

    /**
    * @dev set ship battle attributes
    * @param battleAttrs battle attribute ids
    * @param datas input data array of ShipNFTBattleAttr
    */
    function setShipBattleAttr(uint32[] memory battleAttrs, ShipNFTBattleAttr[] memory datas) external
    {
        require(battleAttrs.length == datas.length, "NFTAttrSource_V1: parameter error");
        require(hasRole(MANAGER_ROLE, _msgSender()), "NFTAttrSource_V1: must have manager role to manage");

        for(uint i=0; i< battleAttrs.length; ++i){
            _shipBattleAttrs[battleAttrs[i]] = datas[i];
        }
    }
}

