// SPDX-License-Identifier: MIT
// Metaline Contracts (Shipyard.sol)

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./Pausable.sol";
import "./Context.sol";

import "./OracleCharger.sol";

import "./WarrantNFT.sol";
import "./ShipNFT.sol";

contract Shipyard is
    Context,
    Pausable,
    AccessControl 
{
    using OracleCharger for OracleCharger.OracleChargerStruct;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    event StartUpgrade_Ship(address indexed userAddr, uint256 indexed shipNFTID, uint256 indexed warrantNFTID, uint16 nextLevel, uint32 finishTime);
    event FinishUpgrade_Ship(address indexed userAddr, uint256 indexed shipNFTID, uint16 newLevel);

    struct ShipUpgradeConf {
        uint256 usdPrice; // upgrade cost usd price, 18 decimal
        uint32 timeCost; // upgrade cost time, in second
        uint16 portIDRequire; // shipyard port id require
        uint16 shipyardLvRequire; // require shipyard level
    }
    struct ShipUpgarding {
        uint16 nextLevel; // new level
        uint32 finishTime; //  finish time, unix timestamp in second
    }

    OracleCharger.OracleChargerStruct public _oracleCharger;

    address public _warrantNFTAddr;
    address public _shipNFTAddr;

    mapping(uint16=>mapping(uint16=>uint24[])) public _buildabelShips; // port id => shipyard level => array of mintable ships (shipType<<16 | shipTypeID)
    mapping(uint24=>mapping(uint16=>ShipUpgradeConf)) public _shipUpgradeConfs; // (shipType<<16 | shipTypeID) => ship level => upgrade config
    mapping(uint256=>ShipUpgarding) public _upgradingShips; // ship nft id => upgrading data

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(MANAGER_ROLE, _msgSender());
        _setupRole(SERVICE_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
    }

    function pause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "Shipyard: must have pauser role to pause"
        );
        _pause();
    }

    function unpause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "Shipyard: must have pauser role to unpause"
        );
        _unpause();
    }
    
    function setTPOracleAddr(address tpOracleAddr) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Shipyard: must have manager role");

        _oracleCharger.setTPOracleAddr(tpOracleAddr);
    }

    function setReceiveIncomeAddr(address incomeAddr) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Shipyard: must have manager role");

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
        require(hasRole(MANAGER_ROLE, _msgSender()), "Shipyard: must have manager role");

        _oracleCharger.addChargeToken(tokenName, tokenAddr, maximumUSDPrice, minimumUSDPrice);
    }

    function removeChargeToken(string memory tokenName) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Shipyard: must have manager role");

        _oracleCharger.removeChargeToken(tokenName);
    }

    function init(
        address warrantNFTAddr,
        address shipNFTAddr
    ) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Shipyard: must have manager role");

        _warrantNFTAddr = warrantNFTAddr;
        _shipNFTAddr = shipNFTAddr;
    }

    function setBuildableShips(uint16 portID, uint8 shipyardLv, uint24[] memory buildableShipArray) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Shipyard: must have manager role");

        _buildabelShips[portID][shipyardLv] = buildableShipArray;
    }
    function clearBuildableShips(uint16 portID, uint8 shipyardLv) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Shipyard: must have manager role");

        delete _buildabelShips[portID][shipyardLv];
    }
    function setUpgradeConf(uint8 shipType, uint16 shipTypeID, uint16[] memory shipLevels, ShipUpgradeConf[] memory confs) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Shipyard: must have manager role");
        require(shipLevels.length == confs.length, "Shipyard: input error");

        for(uint i=0; i< shipLevels.length; ++i){
            _shipUpgradeConfs[(uint24(shipType)<<16 | shipTypeID)][shipLevels[i]] = confs[i];
        }
    }
    function clearUpgradeConf(uint8 shipType, uint16 shipTypeID, uint16[] memory shipLevels) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "Shipyard: must have manager role");

        for(uint i = 0; i< shipLevels.length; ++i){
            delete _shipUpgradeConfs[(uint24(shipType)<<16 | shipTypeID)][shipLevels[i]];
        }
    }

    function mint_Ship(
        address userAddr, 
        uint8 shipType, 
        uint16 shipTypeID,
        uint8 grade,
        uint32 minerAttr,
        uint32 battleAttr,
        uint256 warrantNFTID
    ) external whenNotPaused {
        require(hasRole(MINTER_ROLE, _msgSender()), "Shipyard: must have minter role");
        require(WarrantNFT(_warrantNFTAddr).ownerOf(warrantNFTID) == userAddr, "Shipyard: warrant ownership error");

        // get warrant nft data
        WarrantNFTData memory wdata = WarrantNFT(_warrantNFTAddr).getNftData(warrantNFTID);

        uint24 shipID = (uint24(shipType)<<16 | shipTypeID);
        uint24[] storage shipArray = _buildabelShips[wdata.portID][wdata.shipyardLv];
        uint i=0;
        for(; i< shipArray.length; ++i){
            if(shipID == shipArray[i]){
                break;
            }
        }

        require(i < shipArray.length, "Shipyard: ship not buildable");

        ShipNFT(_shipNFTAddr).mint(userAddr, ShipNFTData({
            shipType:shipType,
            shipTypeID:shipTypeID,
            grade:grade,
            minerAttr:minerAttr,
            battleAttr:battleAttr,
            level:1,
            portID:wdata.portID
        }));
    }

    function startUpgrade_Ship(
        uint256 shipNFTID,
        uint256 usdPrice,
        string memory tokenName,
        uint256 warrantNFTID
    ) external payable whenNotPaused {
        require(_upgradingShips[shipNFTID].nextLevel == 0, "Shipyard: ship is upgrading");
        require(WarrantNFT(_warrantNFTAddr).ownerOf(warrantNFTID) == _msgSender(), "Shipyard: warrant ownership error");
        require(ShipNFT(_shipNFTAddr).ownerOf(shipNFTID) == _msgSender(), "Shipyard: not your ship");

        ShipNFTData memory shipdata = ShipNFT(_shipNFTAddr).getNftData(shipNFTID);

        uint24 shipID = (uint24(shipdata.shipType)<<16 | shipdata.shipTypeID);

        ShipUpgradeConf storage upConf = _shipUpgradeConfs[shipID][shipdata.level];
        require(upConf.usdPrice > 0, "Shipyard: ship upgrade config not exist");
        require(upConf.usdPrice <= usdPrice, "Shipyard: price error");
        
        // get warrant nft data
        WarrantNFTData memory wdata = WarrantNFT(_warrantNFTAddr).getNftData(warrantNFTID);
        require(wdata.portID == upConf.portIDRequire, "Shipyard: portID wrong");
        require(wdata.shipyardLv >= upConf.shipyardLvRequire, "Shipyard: shipyard level require");

        _oracleCharger.charge(tokenName, upConf.usdPrice);

        ShipUpgarding memory upd = ShipUpgarding({
            nextLevel:shipdata.level+1,
            finishTime:uint32(block.timestamp) + upConf.timeCost
        });
        _upgradingShips[shipNFTID] = upd;

        emit StartUpgrade_Ship(_msgSender(), shipNFTID, warrantNFTID, upd.nextLevel, upd.finishTime);
    }

    function finishUpgrade_Ship(
        uint256 shipNFTID
    ) external whenNotPaused {
        require(ShipNFT(_shipNFTAddr).ownerOf(shipNFTID) == _msgSender(), "Shipyard: not your ship");

        ShipUpgarding storage upd = _upgradingShips[shipNFTID];
        require(upd.nextLevel > 0, "Shipyard: ship is not upgrading");
        require(upd.finishTime <= uint32(block.timestamp), "Shipyard: ship upgrade not finish yet");

        ShipNFTData memory shipdata = ShipNFT(_shipNFTAddr).getNftData(shipNFTID);

        shipdata.level = upd.nextLevel;

        ShipNFT(_shipNFTAddr).modNftData(shipNFTID, shipdata);

        delete _upgradingShips[shipNFTID];

        emit FinishUpgrade_Ship(_msgSender(), shipNFTID, shipdata.level);
    }
}
