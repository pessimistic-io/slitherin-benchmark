// SPDX-License-Identifier: MIT
// Metaline Contracts (WarrantIssuer.sol)

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./Pausable.sol";
import "./Context.sol";

import "./OracleCharger.sol";

import "./WarrantNFT.sol";

contract WarrantIssuer is
    Context,
    Pausable,
    AccessControl 
{
    using OracleCharger for OracleCharger.OracleChargerStruct;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

    OracleCharger.OracleChargerStruct public _oracleCharger;

    address public _warrantNFTAddr;

    mapping(uint16=>uint256) public _warrantPrices; // port id => usd price
    mapping(uint16=>mapping(uint8=>mapping(uint16=>uint256))) _warrantUpgradePrice; // port id => upgrade type => level => usd price

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(MANAGER_ROLE, _msgSender());
    }

    function pause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "WarrantIssuer: must have pauser role to pause"
        );
        _pause();
    }

    function unpause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "WarrantIssuer: must have pauser role to unpause"
        );
        _unpause();
    }
    
    function setTPOracleAddr(address tpOracleAddr) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "WarrantIssuer: must have manager role");

        _oracleCharger.setTPOracleAddr(tpOracleAddr);
    }

    function setReceiveIncomeAddr(address incomeAddr) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "WarrantIssuer: must have manager role");

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
        require(hasRole(MANAGER_ROLE, _msgSender()), "WarrantIssuer: must have manager role");

        _oracleCharger.addChargeToken(tokenName, tokenAddr, maximumUSDPrice, minimumUSDPrice);
    }

    function removeChargeToken(string memory tokenName) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "WarrantIssuer: must have manager role");

        _oracleCharger.removeChargeToken(tokenName);
    }

    function init(
        address warrantNFTAddr
    ) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "WarrantIssuer: must have manager role");

        _warrantNFTAddr = warrantNFTAddr;
    }

    // usdPrice: 18 decimal
    function setWarrantPrice(uint16 portID, uint256 usdPrice) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "WarrantIssuer: must have manager role");

        _warrantPrices[portID] = usdPrice;
    }
    // usdPrice: 18 decimal
    function setWarrantUpgradePrice(uint16 portID, uint8 upgradeType, uint16 level, uint256 usdPrice) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "WarrantIssuer: must have manager role");

        _warrantUpgradePrice[portID][upgradeType][level] = usdPrice;
    }
    function clearWarrantUpgradePrice(uint16 portID, uint8 upgradeType, uint16 level) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "WarrantIssuer: must have manager role");

        delete _warrantUpgradePrice[portID][upgradeType][level];
    }

    function mint_MTTWarrant(uint16 portID, uint256 usdPrice, string memory tokenName) external payable whenNotPaused {
        uint256 _usdPrice = _warrantPrices[portID];
        require(_usdPrice > 0, "WarrantIssuer: port not exist");
        require(_usdPrice <= usdPrice, "WarrantIssuer: price parameter error");

        _oracleCharger.charge(tokenName, _usdPrice);

        WarrantNFT(_warrantNFTAddr).mint(_msgSender(), WarrantNFTData({
            portID:portID,
            storehouseLv:1,
            factoryLv:1,
            shopLv:1,
            shipyardLv:0,
            createTm:uint32(block.timestamp)
        }));
    }

    function upgrade_MTTWarrant(
        uint256 warrantNFTID,
        uint8 upgradeType,
        uint256 usdPrice,
        string memory tokenName
    ) external payable whenNotPaused{
        require(WarrantNFT(_warrantNFTAddr).ownerOf(warrantNFTID) == _msgSender(), "WarrantIssuer: ownership error");

        // get warrant nft data
        WarrantNFTData memory wdata = WarrantNFT(_warrantNFTAddr).getNftData(warrantNFTID);
        uint256 _usdPrice = 0;

        mapping(uint8=>mapping(uint16=>uint256)) storage upPrices = _warrantUpgradePrice[wdata.portID];

        if(upgradeType == 1) { // upgrade storehouse
            _usdPrice = upPrices[upgradeType][wdata.storehouseLv];
            ++wdata.storehouseLv;
        }
        else if(upgradeType == 2) { // upgrade factory
            _usdPrice = upPrices[upgradeType][wdata.factoryLv];
            ++wdata.factoryLv;
        }
        else if(upgradeType == 3) { // upgrade shop
            _usdPrice = upPrices[upgradeType][wdata.shopLv];
            ++wdata.shopLv;
        }
        else if(upgradeType == 4) { // upgrade shipyard
            _usdPrice = upPrices[upgradeType][wdata.shipyardLv];
            ++wdata.shipyardLv;
        }
        
        require(_usdPrice > 0 && _usdPrice <= usdPrice, "WarrantIssuer: price error");

        _oracleCharger.charge(tokenName, _usdPrice);

        WarrantNFT(_warrantNFTAddr).modNftData(warrantNFTID, wdata);
    }
}
