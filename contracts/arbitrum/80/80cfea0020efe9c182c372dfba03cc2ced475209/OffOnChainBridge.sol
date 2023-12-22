// SPDX-License-Identifier: MIT
// Metaline Contracts (OffOnChainBridge.sol)

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./Pausable.sol";
import "./Context.sol";

import "./MTT.sol";
import "./MTTGold.sol";
import "./WarrantNFT.sol";

import "./TransferHelper.sol";
import "./OracleCharger.sol";

contract OffOnChainBridge is
    Context,
    Pausable,
    AccessControl 
{
    using OracleCharger for OracleCharger.OracleChargerStruct;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    event Off2OnChain_MTTGold(address userAddr, uint256 goldValue);
    event On2OffChain_MTTGold(address userAddr, uint256 goldValue);
    
    OracleCharger.OracleChargerStruct public _oracleCharger;
    
    address public _warrantNFTAddr;
    address public _MTTAddr;
    address public _MTTGoldAddr;

    mapping(uint16=>mapping(uint16=>uint256)) public _shopGoldMaxGen; // port id => shop level => max gold generate per second (18 decimal)
    mapping(uint256=>uint32) public _lastWarrantGenGoldTm; // warrant id => last generate gold time, unix timestamp in second

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
            "OffOnChainBridge: must have pauser role to pause"
        );
        _pause();
    }

    function unpause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "OffOnChainBridge: must have pauser role to unpause"
        );
        _unpause();
    }
    
    function setTPOracleAddr(address tpOracleAddr) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "OffOnChainBridge: must have manager role");

        _oracleCharger.setTPOracleAddr(tpOracleAddr);
    }

    function setReceiveIncomeAddr(address incomeAddr) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "OffOnChainBridge: must have manager role");

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
        require(hasRole(MANAGER_ROLE, _msgSender()), "OffOnChainBridge: must have manager role");

        _oracleCharger.addChargeToken(tokenName, tokenAddr, maximumUSDPrice, minimumUSDPrice);
    }

    function removeChargeToken(string memory tokenName) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "OffOnChainBridge: must have manager role");

        _oracleCharger.removeChargeToken(tokenName);
    }
    
    function init(
        address warrantNFTAddr,
        address MTTAddr,
        address MTTGoldAddr
    ) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "OffOnChainBridge: must have manager role");

        _warrantNFTAddr = warrantNFTAddr;
        _MTTAddr = MTTAddr;
        _MTTGoldAddr = MTTGoldAddr;
    }

    // maxGoldGen: 18 decimal
    function setShopGoldMaxGen(uint16 portID, uint16 shopLv, uint256 maxGoldGenPerSec) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "OffOnChainBridge: must have manager role");

        _shopGoldMaxGen[portID][shopLv] = maxGoldGenPerSec;
    }

    function mint_MTTGold(
        address userAddr, 
        uint256 goldValue, 
        uint256 warrantNFTID
    ) external whenNotPaused {
        require(hasRole(MINTER_ROLE, _msgSender()), "OffOnChainBridge: must have minter role");
        require(WarrantNFT(_warrantNFTAddr).ownerOf(warrantNFTID) == userAddr, "OffOnChainBridge: warrant ownership error");
        require(goldValue > 0, "OffOnChainBridge: parameter error");

        // get warrant nft data
        WarrantNFTData memory wdata = WarrantNFT(_warrantNFTAddr).getNftData(warrantNFTID);

        uint32 lasttm = _lastWarrantGenGoldTm[warrantNFTID];
        if(lasttm == 0){
            lasttm = wdata.createTm;
        }
        require(block.timestamp > lasttm, "OffOnChainBridge: time error");

        // calc max gold gen
        uint256 maxGoldGenPerSec = _shopGoldMaxGen[wdata.portID][wdata.shopLv];
        uint256 maxGoldGen = maxGoldGenPerSec * (block.timestamp - lasttm);
        require(maxGoldGen >= goldValue, "OffOnChainBridge: gold value overflow");

        _lastWarrantGenGoldTm[warrantNFTID] = uint32(block.timestamp);

        MTTGold(_MTTGoldAddr).mint(userAddr, goldValue);
    }

    function off2onChain_MTTGold(address userAddr, uint256 goldValue) external whenNotPaused {
        require(hasRole(SERVICE_ROLE, _msgSender()), "OffOnChainBridge: must have service role");
        require(MTTGold(_MTTGoldAddr).balanceOf(address(this)) >= goldValue, "OffOnChainBridge: insufficient MTTGold");

        TransferHelper.safeTransferFrom(_MTTGoldAddr, address(this), userAddr, goldValue);
        
        emit Off2OnChain_MTTGold(userAddr, goldValue);
    }

    function on2offChain_MTTGold(uint256 goldValue) external whenNotPaused {
        require(MTTGold(_MTTGoldAddr).balanceOf(address(_msgSender())) >= goldValue, "OffOnChainBridge: insufficient MTTGold");

        TransferHelper.safeTransferFrom(_MTTGoldAddr, _msgSender(), address(this), goldValue);

        emit On2OffChain_MTTGold(_msgSender(), goldValue);
    }
}
