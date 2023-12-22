// SPDX-License-Identifier: MIT
// Metaline Contracts (HeroPetTrain.sol)

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./Pausable.sol";
import "./Context.sol";

import "./OracleCharger.sol";

import "./WarrantNFT.sol";
import "./HeroNFT.sol";
import "./HeroNFTCodec.sol";

import "./MTTGold.sol";

contract HeroPetTrain is
    Context,
    Pausable,
    AccessControl 
{
    using OracleCharger for OracleCharger.OracleChargerStruct;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");

    event StartUpgrade_HeroOrPet(address indexed userAddr, uint256 indexed heroNFTID, uint256 indexed warrantNFTID, uint16 nextLevel, uint32 finishTime);
    event FinishUpgrade_HeroOrPet(address indexed userAddr, uint256 indexed heroNFTID, uint16 newLevel);
    
    event StartUpStarLv_Hero(address indexed userAddr, uint256 indexed heroNFTID, uint256 indexed warrantNFTID, uint16 nextStarLevel, uint32 finishTime);
    event FinishUpStarLv_Hero(address indexed userAddr, uint256 indexed heroNFTID, uint16 newStarLevel);
    
    struct HeroPetUpgradeConf {
        uint256 goldPrice; // upgrade cost gold price, 18 decimal
        uint32 timeCost; // upgrade cost time, in second
        uint16 portIDRequire; // train port id require
    }
    struct HeroPetUpgarding {
        uint16 nextLevel; // new level
        uint32 finishTime; //  finish time, unix timestamp in second
    }

    struct HeroUpStarLevelConf {
        uint256 usdPrice; // upgrade cost usd price, 18 decimal
        uint32 timeCost; // upgrade cost time, in second
        uint16 heroLevelRequire; // hero level require
        uint16 portIDRequire; // train port id require
    }
    struct HeroStarLvUping {
        uint8 nextStarLevel; // new star level
        uint32 finishTime; //  finish time, unix timestamp in second
    }

    OracleCharger.OracleChargerStruct public _oracleCharger;

    address public _warrantNFTAddr;
    address public _heroNFTAddr;
    address public _MTTGoldAddr;
    
    mapping(uint16=>mapping(uint8=>mapping(uint16=>HeroPetUpgradeConf))) public _heropetUpgradeConfs; // nfttype => job/petId => level => upgrade config
    mapping(uint256=>HeroPetUpgarding) public _upgradingHeroPets; // hero/pet nft id => upgrading data
    
    mapping(uint8=>mapping(uint16=>HeroUpStarLevelConf)) public _heroStarLvUpConfs; // job => level => star level up config
    mapping(uint256=>HeroStarLvUping) public _upingStarLvHeros; // hero nft id => star level uping data

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(MANAGER_ROLE, _msgSender());
        _setupRole(SERVICE_ROLE, _msgSender());
    }

    function pause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "HeroPetTrain: must have pauser role to pause"
        );
        _pause();
    }

    function unpause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "HeroPetTrain: must have pauser role to unpause"
        );
        _unpause();
    }
    
    function setTPOracleAddr(address tpOracleAddr) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "HeroPetTrain: must have manager role");

        _oracleCharger.setTPOracleAddr(tpOracleAddr);
    }

    function setReceiveIncomeAddr(address incomeAddr) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "HeroPetTrain: must have manager role");

        _oracleCharger.setReceiveIncomeAddr(incomeAddr);
    }

    // maximumUSDPrice = 0: no limit
    // minimumUSDPrice = 0: no limit
    function addChargeToken(
        string memory tokenName, 
        address tokenAddr, 
        uint256 maximumUSDPrice, 
        uint256 minimumUSDPrice
    ) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "HeroPetTrain: must have manager role");

        _oracleCharger.addChargeToken(tokenName, tokenAddr, maximumUSDPrice, minimumUSDPrice);
    }

    function removeChargeToken(string memory tokenName) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "HeroPetTrain: must have manager role");

        _oracleCharger.removeChargeToken(tokenName);
    }

    function init(
        address warrantNFTAddr,
        address heroNFTAddr,
        address MTTGoldAddr
    ) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "HeroPetTrain: must have manager role");

        _warrantNFTAddr = warrantNFTAddr;
        _heroNFTAddr = heroNFTAddr;
        _MTTGoldAddr = MTTGoldAddr;
    }
    
    function setUpgradeConf(uint16 nftType, uint8 joborpetid, uint16[] memory levels, HeroPetUpgradeConf[] memory confs) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "HeroPetTrain: must have manager role");
        require(levels.length == confs.length, "HeroPetTrain: input error");

        for(uint i= 0; i< levels.length; ++i){
            _heropetUpgradeConfs[nftType][joborpetid][levels[i]] = confs[i];
        }
    }
    function clearUpgradeConf(uint16 nftType, uint8 joborpetid, uint16[] memory levels) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "HeroPetTrain: must have manager role");

        for(uint i= 0; i< levels.length; ++i){
            delete _heropetUpgradeConfs[nftType][joborpetid][levels[i]];
        }
    }
    
    function setStarLvUpConf(uint8 job, uint16 level, HeroUpStarLevelConf memory conf) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "HeroPetTrain: must have manager role");

        _heroStarLvUpConfs[job][level] = conf;
    }
    function clearStarLvUpConf(uint8 job, uint16 level) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "HeroPetTrain: must have manager role");

        delete _heroStarLvUpConfs[job][level];
    }
    
    function startUpgrade_HeroOrPet(
        uint256 heroNFTID,
        uint256 goldPrice,
        uint256 warrantNFTID
    ) external whenNotPaused {
        require(_upgradingHeroPets[heroNFTID].nextLevel == 0, "HeroPetTrain: hero or pet is upgrading");
        require(WarrantNFT(_warrantNFTAddr).ownerOf(warrantNFTID) == _msgSender(), "HeroPetTrain: warrant ownership error");
        require(HeroNFT(_heroNFTAddr).ownerOf(heroNFTID) == _msgSender(), "HeroPetTrain: not your hero or pet");
        // TO DO : check freeze?

        HeroNFTDataBase memory hdb = HeroNFT(_heroNFTAddr).getNftData(heroNFTID);
        IHeroNFTCodec_V1 codec = IHeroNFTCodec_V1(HeroNFT(_heroNFTAddr).getCodec());

        uint16 level;
        HeroPetUpgradeConf memory upConf;
        if(hdb.nftType == 1) { // hero 
            HeroNFTFixedData_V1 memory hndata = codec.getHeroNftFixedData(hdb);
            HeroNFTWriteableData_V1 memory wdata = codec.getHeroNftWriteableData(hdb);

            level = wdata.level;
            upConf = _heropetUpgradeConfs[hdb.nftType][hndata.job][level];
        } 
        else if(hdb.nftType == 2) { // pet
            HeroPetNFTFixedData_V1 memory hndata = codec.getHeroPetNftFixedData(hdb);
            HeroPetNFTWriteableData_V1 memory wdata = codec.getHeroPetNftWriteableData(hdb);
            
            level = wdata.level;
            upConf = _heropetUpgradeConfs[hdb.nftType][hndata.petId][level];
        }
        else {
            revert("HeroPetTrain: nft type error");
        }

        require(upConf.goldPrice > 0, "HeroPetTrain: hero or pet upgrade config not exist");
        require(upConf.goldPrice <= goldPrice, "HeroPetTrain: price error");
        
        // get warrant nft data
        WarrantNFTData memory wadata = WarrantNFT(_warrantNFTAddr).getNftData(warrantNFTID);
        require(wadata.portID == upConf.portIDRequire, "HeroPetTrain: portID wrong");

        // burn gold
        MTTGold(_MTTGoldAddr).burnFrom(_msgSender(), upConf.goldPrice);

        HeroPetUpgarding memory upd = HeroPetUpgarding({
            nextLevel:level+1,
            finishTime:uint32(block.timestamp) + upConf.timeCost
        });
        _upgradingHeroPets[heroNFTID] = upd;

        emit StartUpgrade_HeroOrPet(_msgSender(), heroNFTID, warrantNFTID, upd.nextLevel, upd.finishTime);
    }

    function finishUpgrade_HeroOrPet(
        uint256 heroNFTID
    ) external whenNotPaused {
        
        require(HeroNFT(_heroNFTAddr).ownerOf(heroNFTID) == _msgSender(), "HeroPetTrain: not your hero or pet");
        // TO DO : check freeze?

        HeroPetUpgarding storage upd = _upgradingHeroPets[heroNFTID];
        require(upd.nextLevel > 0, "HeroPetTrain: hero or pet is not upgrading");
        require(upd.finishTime <= uint32(block.timestamp), "HeroPetTrain: hero or pet upgrade not finish yet");

        HeroNFTDataBase memory hdb = HeroNFT(_heroNFTAddr).getNftData(heroNFTID);
        IHeroNFTCodec_V1 codec = IHeroNFTCodec_V1(HeroNFT(_heroNFTAddr).getCodec());

        uint256 writeableData;
        if(hdb.nftType == 1) { // hero 
            HeroNFTWriteableData_V1 memory wdata = codec.getHeroNftWriteableData(hdb);
            wdata.level = upd.nextLevel;

            writeableData = codec.toHeroNftWriteableData(wdata);
        } 
        else if(hdb.nftType == 2) { // pet
            HeroPetNFTWriteableData_V1 memory wdata = codec.getHeroPetNftWriteableData(hdb);
            wdata.level = upd.nextLevel;
            
            writeableData = codec.toHeroPetNftWriteableData(wdata);
        }
        else {
            revert("HeroPetTrain: nft type error");
        }
        
        HeroNFT(_heroNFTAddr).modNftData(heroNFTID, writeableData);

        emit FinishUpgrade_HeroOrPet(_msgSender(), heroNFTID, upd.nextLevel);

        delete _upgradingHeroPets[heroNFTID];
    }

    function startUpStarLv_Hero(
        uint256 heroNFTID,
        uint256 usdPrice,
        string memory tokenName,
        uint256 warrantNFTID
    ) external payable whenNotPaused {
        require(_upingStarLvHeros[heroNFTID].nextStarLevel == 0, "HeroPetTrain: hero is upgrading");
        require(WarrantNFT(_warrantNFTAddr).ownerOf(warrantNFTID) == _msgSender(), "HeroPetTrain: warrant ownership error");
        require(HeroNFT(_heroNFTAddr).ownerOf(heroNFTID) == _msgSender(), "HeroPetTrain: not your hero");
        // TO DO : check freeze?

        HeroNFTDataBase memory hdb = HeroNFT(_heroNFTAddr).getNftData(heroNFTID);
        IHeroNFTCodec_V1 codec = IHeroNFTCodec_V1(HeroNFT(_heroNFTAddr).getCodec());

        require(hdb.nftType == 1, "HeroPetTrain: not hero nft"); // hero

        HeroNFTFixedData_V1 memory hndata = codec.getHeroNftFixedData(hdb);
        HeroNFTWriteableData_V1 memory wdata = codec.getHeroNftWriteableData(hdb);

        HeroUpStarLevelConf memory upConf = _heroStarLvUpConfs[hndata.job][wdata.starLevel];
        
        require(wdata.level >= upConf.heroLevelRequire, "HeroPetTrain: hero level not enough");

        require(upConf.usdPrice > 0, "HeroPetTrain: hero upgrade config not exist");
        require(upConf.usdPrice <= usdPrice, "HeroPetTrain: price error");
        
        // get warrant nft data
        WarrantNFTData memory wadata = WarrantNFT(_warrantNFTAddr).getNftData(warrantNFTID);
        require(wadata.portID == upConf.portIDRequire, "HeroPetTrain: portID wrong");

        // charge
        _oracleCharger.charge(tokenName, upConf.usdPrice);

        HeroStarLvUping memory upd = HeroStarLvUping({
            nextStarLevel:wdata.starLevel+1,
            finishTime:uint32(block.timestamp) + upConf.timeCost
        });
        _upingStarLvHeros[heroNFTID] = upd;

        emit StartUpStarLv_Hero(_msgSender(), heroNFTID, warrantNFTID, upd.nextStarLevel, upd.finishTime);
    }

    function finishUpStarLv_Hero(
        uint256 heroNFTID
    ) external whenNotPaused {
        
        require(HeroNFT(_heroNFTAddr).ownerOf(heroNFTID) == _msgSender(), "HeroPetTrain: not your hero");
        // TO DO : check freeze?

        HeroStarLvUping storage upd = _upingStarLvHeros[heroNFTID];
        require(upd.nextStarLevel > 0, "HeroPetTrain: hero is not upgrading");
        require(upd.finishTime <= uint32(block.timestamp), "HeroPetTrain: hero upgrade not finish yet");

        HeroNFTDataBase memory hdb = HeroNFT(_heroNFTAddr).getNftData(heroNFTID);
        IHeroNFTCodec_V1 codec = IHeroNFTCodec_V1(HeroNFT(_heroNFTAddr).getCodec());
        
        require(hdb.nftType == 1, "HeroPetTrain: not hero nft"); // hero

        HeroNFTWriteableData_V1 memory wdata = codec.getHeroNftWriteableData(hdb);
        wdata.starLevel = upd.nextStarLevel;

        uint256 writeableData = codec.toHeroNftWriteableData(wdata);
        
        HeroNFT(_heroNFTAddr).modNftData(heroNFTID, writeableData);

        delete _upingStarLvHeros[heroNFTID];

        emit FinishUpStarLv_Hero(_msgSender(), heroNFTID, wdata.starLevel);
    }
}
