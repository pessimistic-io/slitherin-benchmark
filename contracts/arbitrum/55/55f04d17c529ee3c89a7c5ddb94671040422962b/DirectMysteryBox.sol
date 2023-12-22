// SPDX-License-Identifier: MIT
// Metaline Contracts (DirectMysteryBox.sol)

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./Pausable.sol";
import "./Context.sol";
import "./IERC20.sol";
import "./IERC1155.sol";

import "./TransferHelper.sol";
import "./GasFeeCharger.sol";

import "./MBRandomSourceBase.sol";

contract DirectMysteryBox is 
    Context,
    Pausable,
    AccessControl,
    IOracleRandComsumer
{
    using GasFeeCharger for GasFeeCharger.MethodExtraFees;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant RAND_ROLE = keccak256("RAND_ROLE");

    event SetOnSaleDirectMB(uint32 indexed directMBID, DirectOnSaleMB saleConfig, DirectOnSaleMBRunTime saleData);

    event DirectMBOpen(address indexed useAddr, uint32 indexed directMBID);
    event DirectMBGetResult(address indexed useAddr, uint32 indexed directMBID, MBContentMinter1155Info[] sfts, MBContentMinterNftInfo[] nfts);

    event DirectMBBatchOpen(address indexed useAddr, uint32 indexed directMBID, uint256 batchCount);
    event DirectMBBatchGetResult(address indexed useAddr, uint32 indexed directMBID, MBContentMinter1155Info[] sfts, MBContentMinterNftInfo[] nfts);

    struct DirectMBOpenRecord {
        address userAddr;
        uint32 directMBID;
        uint8 batchCount;
    }

    struct DirectOnSaleMB {
        address randsource; // mystery box address
        uint32 mysteryType; // mystery type

        address tokenAddr; // charge token addr, could be 20 or 1155
        uint256 tokenId; // =0 means 20 token, else 1155 token
        uint256 price; // price value

        uint64 beginTime; // start sale timeStamp in seconds since unix epoch, =0 ignore this condition
        uint64 endTime; // end sale timeStamp in seconds since unix epoch, =0 ignore this condition

        uint64 renewTime; // how long in seconds for each renew
        uint256 renewCount; // how many count put on sale for each renew
    }
    
    struct DirectOnSaleMBRunTime {
        // runtime data -------------------------------------------------------
        uint64 nextRenewTime; // after this timeStamp in seconds since unix epoch, will put at max [renewCount] on sale

        // config & runtime data ----------------------------------------------
        uint256 countLeft; // how many boxies left
    }

    mapping(uint256=>DirectMBOpenRecord) public _openedRecord; // indexed by oracleRand request id
    mapping(uint32=>DirectOnSaleMB) public _onsaleMB; // indexed by directMBID
    mapping(uint32=>DirectOnSaleMBRunTime) public _onsaleMBDatas; // indexed by directMBID
    
    address public _receiveIncomAddress;

    // Method extra fee
    // For smart contract method which need extra transaction by other service, we define extra fee
    // extra fee charge by method call tx with `value` paramter, and send to target service wallet address
    GasFeeCharger.MethodExtraFees _methodExtraFees;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'Metaline: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(PAUSER_ROLE, _msgSender());
        _setupRole(MANAGER_ROLE, _msgSender());
        _setupRole(RAND_ROLE, _msgSender());
    }

    function pause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "DirectMysteryBox: must have pauser role to pause"
        );
        _pause();
    }

    function unpause() public {
        require(
            hasRole(PAUSER_ROLE, _msgSender()),
            "DirectMysteryBox: must have pauser role to unpause"
        );
        _unpause();
    }

    function setOnSaleDirectMB(uint32 directMBID, DirectOnSaleMB memory saleConfig, DirectOnSaleMBRunTime memory saleData) external whenNotPaused {
        require(hasRole(MANAGER_ROLE, _msgSender()), "DirectMysteryBox: must have manager role to manage");

        if(saleConfig.renewTime > 0)
        {
            saleData.nextRenewTime = (uint64)(block.timestamp + saleConfig.renewTime);
        }

        _onsaleMB[directMBID] = saleConfig;
        _onsaleMBDatas[directMBID] = saleData;

        emit SetOnSaleDirectMB(directMBID, saleConfig, saleData);
    }

    function setReceiveIncomeAddress(address incomAddr) external {
        require(hasRole(MANAGER_ROLE, _msgSender()), "DirectMysteryBox: must have manager role to manage");

        _receiveIncomAddress = incomAddr;
    }

    /**
    * @dev set smart contract method invoke by transaction with extra fee
    *
    * Requirements:
    * - caller must have `MANAGER_ROLE`
    *
    * @param methodKey key of which method need extra fee
    * @param value extra fee value
    * @param target target address where extra fee goes to
    */
    function setMethodExtraFee(uint8 methodKey, uint256 value, address target) external {
        require(
            hasRole(MANAGER_ROLE, _msgSender()),
            "DirectMysteryBox: must have manager role"
        );

        _methodExtraFees.setMethodExtraFee(methodKey, value, target);
    }

    /**
    * @dev cancel smart contract method invoke by transaction with extra fee
    *
    * Requirements:
    * - caller must have `MANAGER_ROLE`
    *
    * @param methodKey key of which method need cancel extra fee
    */
    function removeMethodExtraFee(uint8 methodKey) external {
        require(
            hasRole(MANAGER_ROLE, _msgSender()),
            "DirectMysteryBox: must have manager role"
        );

        _methodExtraFees.removeMethodExtraFee(methodKey);
    }
    
    function _checkSellCondition(DirectOnSaleMB storage onSalePair, DirectOnSaleMBRunTime storage onSalePairData) internal {
        if(onSalePair.beginTime > 0)
        {
            require(block.timestamp >= onSalePair.beginTime, "DirectMysteryBox: sale not begin");
        }
        if(onSalePair.endTime > 0)
        {
            require(block.timestamp <= onSalePair.endTime, "DirectMysteryBox: sale finished");
        }

        if(onSalePair.renewTime > 0)
        {
            if(block.timestamp > onSalePairData.nextRenewTime)
            {
                onSalePairData.nextRenewTime = (uint64)(onSalePairData.nextRenewTime + onSalePair.renewTime * (1 + ((block.timestamp - onSalePairData.nextRenewTime) / onSalePair.renewTime)));
                onSalePairData.countLeft = onSalePair.renewCount;
            }
        }
    }

    
    function _chargeByDesiredCount(DirectOnSaleMB storage onSalePair, DirectOnSaleMBRunTime storage onSalePairData, uint256 count, uint256 gasfee) 
        internal returns (uint256 realCount)
    {
        realCount = count;
        if(realCount > onSalePairData.countLeft)
        {
            realCount = onSalePairData.countLeft;
        }

        require(realCount > 0, "DirectMysteryBox: insufficient mystery box");

        onSalePairData.countLeft -= realCount;

        if(onSalePair.price > 0){
            uint256 realPrice = onSalePair.price * realCount;

            if(realPrice > 0){
                if(onSalePair.tokenAddr == address(0)){
                    uint256 valueLeft = msg.value - gasfee;
                    require(valueLeft >= realPrice, "DirectMysteryBox: insufficient value");

                    // receive eth
                    (bool sent, ) = _receiveIncomAddress.call{value:realPrice}("");
                    require(sent, "DirectMysteryBox: transfer income error");
                    if(valueLeft > realPrice){
                        (sent, ) = msg.sender.call{value:(valueLeft - realPrice)}(""); // send back
                        require(sent, "MysteryBoxShop: transfer income error");
                    }
                }
                else if(onSalePair.tokenId > 0)
                {
                    // 1155
                    require(IERC1155(onSalePair.tokenAddr).balanceOf( _msgSender(), onSalePair.tokenId) >= realPrice , "DirectMysteryBox: erc1155 insufficient token");
                    IERC1155(onSalePair.tokenAddr).safeTransferFrom(_msgSender(), _receiveIncomAddress, onSalePair.tokenId, realPrice, "direct mb");
                }
                else{
                    // 20
                    require(IERC20(onSalePair.tokenAddr).balanceOf(_msgSender()) >= realPrice , "DirectMysteryBox: erc20 insufficient token");
                    TransferHelper.safeTransferFrom(onSalePair.tokenAddr, _msgSender(), _receiveIncomAddress, realPrice);
                }
            }
        }

    }

    function openMB(uint32 directMBID) external payable lock whenNotPaused {
        require(tx.origin == _msgSender(), "DirectMysteryBox: only for outside account");
        require(_receiveIncomAddress != address(0), "DirectMysteryBox: receive income address not set");
        
        DirectOnSaleMB storage onSalePair = _onsaleMB[directMBID];
        DirectOnSaleMBRunTime storage onSalePairData = _onsaleMBDatas[directMBID];
        require(address(onSalePair.randsource) != address(0), "DirectMysteryBox: mystery box not on sale");

        address rndAddr = MBRandomSourceBase(onSalePair.randsource).getRandSource();
        require(rndAddr != address(0), "DirectMysteryBox: rand address wrong");

        uint256 gasfee = _methodExtraFees.chargeMethodExtraFee(1); // charge openMB extra fee
        
        _checkSellCondition(onSalePair, onSalePairData);
        _chargeByDesiredCount(onSalePair, onSalePairData, 1, gasfee);

        // request random number
        uint256 reqid = IRandom(rndAddr).oracleRand();

        DirectMBOpenRecord storage openRec = _openedRecord[reqid];
        openRec.directMBID = directMBID;
        openRec.userAddr = _msgSender();
        openRec.batchCount = 0;

        // emit direct mb open event
        emit DirectMBOpen(_msgSender(), directMBID);
    }

    function batchOpenMB(uint32 directMBID, uint8 batchCount) external payable lock whenNotPaused {
        require(tx.origin == _msgSender(), "DirectMysteryBox: only for outside account");
        require(_receiveIncomAddress != address(0), "DirectMysteryBox: receive income address not set");
        
        DirectOnSaleMB storage onSalePair = _onsaleMB[directMBID];
        DirectOnSaleMBRunTime storage onSalePairData = _onsaleMBDatas[directMBID];
        require(address(onSalePair.randsource) != address(0), "DirectMysteryBox: mystery box not on sale");

        require(batchCount >0 && batchCount <= 50, "DirectMysteryBox: batch open count must <= 50");

        address rndAddr = MBRandomSourceBase(onSalePair.randsource).getRandSource();
        require(rndAddr != address(0), "DirectMysteryBox: rand address wrong");

        uint256 gasfee = _methodExtraFees.chargeMethodExtraFee(2); // charge batchOpenMB extra fee

        _checkSellCondition(onSalePair, onSalePairData);
        _chargeByDesiredCount(onSalePair, onSalePairData, batchCount, gasfee);

        // request random number
        uint256 reqid = IRandom(rndAddr).oracleRand();

        DirectMBOpenRecord storage openRec = _openedRecord[reqid];
        openRec.directMBID = directMBID;
        openRec.userAddr = _msgSender();
        openRec.batchCount = batchCount;

        // emit direct mb open event
        emit DirectMBBatchOpen(_msgSender(), directMBID, batchCount);
    }

    // get rand number, real open mystery box
    function oracleRandResponse(uint256 reqid, uint256 randnum) override external {
        require(hasRole(RAND_ROLE, _msgSender()), "DirectMysteryBox: must have rand role");

        DirectMBOpenRecord storage openRec = _openedRecord[reqid];
        
        DirectOnSaleMB storage onSalePair = _onsaleMB[openRec.directMBID];
        require(address(onSalePair.randsource) != address(0), "DirectMysteryBox: mystery box not on sale");

        address rndAddr = MBRandomSourceBase(onSalePair.randsource).getRandSource();
        require(rndAddr != address(0), "DirectMysteryBox: rand address wrong");

        require(openRec.userAddr != address(0), "DirectMysteryBox: user address wrong");

        if(openRec.batchCount > 0){
            (MBContentMinter1155Info[] memory sfts, MBContentMinterNftInfo[] memory nfts) 
                = MBRandomSourceBase(onSalePair.randsource).batchRandomAndMint(randnum, onSalePair.mysteryType, openRec.userAddr, openRec.batchCount);

            emit DirectMBBatchGetResult(openRec.userAddr, openRec.directMBID, sfts, nfts);
        }
        else {
            (MBContentMinter1155Info[] memory sfts, MBContentMinterNftInfo[] memory nfts) 
                = MBRandomSourceBase(onSalePair.randsource).randomAndMint(randnum, onSalePair.mysteryType, openRec.userAddr);

            emit DirectMBGetResult(openRec.userAddr, openRec.directMBID, sfts, nfts);
        }
        
        delete _openedRecord[reqid];
    }
}
