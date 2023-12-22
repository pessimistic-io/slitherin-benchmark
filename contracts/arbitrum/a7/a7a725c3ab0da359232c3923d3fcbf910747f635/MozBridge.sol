// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "./Vault.sol";
import "./Controller.sol";
import "./IPlugin.sol";

// imports
import "./Ownable.sol";
import "./ILayerZeroReceiver.sol";
import "./ILayerZeroEndpoint.sol";
import "./ILayerZeroUserApplicationConfig.sol";


contract MozBridge is Ownable, ILayerZeroReceiver, ILayerZeroUserApplicationConfig {
    //---------------------------------------------------------------------------
    // CONSTANTS
    uint16 internal constant TYPE_REQUEST_SNAPSHOT = 1;
    uint16 internal constant TYPE_REPORT_SNAPSHOT  = 2;
    uint16 internal constant TYPE_REQUEST_SETTLE   = 3;
    uint16 internal constant TYPE_REPORT_SETTLE    = 4;
    uint16 internal constant TYPE_STAKE_ASSETS     = 5;
    uint16 internal constant TYPE_UNSTAKE_ASSETS   = 6;

    uint16 internal constant TYPE_ACTION_RETRY = 7;
    uint16 internal constant TYPE_SNAPSHOT_RETRY = 8;
    uint16 internal constant TYPE_SETTLE_RETRY = 9;
    uint16 internal constant TYPE_REPORT_SNAPSHOT_RETRY = 10;
    uint16 internal constant TYPE_REPORT_SETTLE_RETRY = 11;

    //---------------------------------------------------------------------------
    // STRUCTS
    struct LzTxObj {
        uint256 dstGasForCall;
        uint256 dstNativeAmount;
        bytes dstNativeAddr;
    }

    struct Snapshot {
        uint256 depositRequestAmount;
        uint256 withdrawRequestAmountMLP;
        uint256 totalStablecoin;
        uint256 totalMozaicLp; // Mozaic "LP"
        uint256[] amounts;
    }

    //---------------------------------------------------------------------------
    // VARIABLES
    ILayerZeroEndpoint public immutable layerZeroEndpoint;
    
    uint16 public immutable mainChainId;

    Vault public  vault;
    
    Controller public controller;
    
    mapping(uint16 => bytes) public bridgeLookup;
    
    mapping(uint16 => mapping(uint16 => uint256)) public gasLookup;
    
    bool public useLayerZeroToken;
    
    //---------------------------------------------------------------------------
    // EVENTS
    event ReceiveMsg(
        uint16 srcChainId,
        address from,
        uint16 funType,
        bytes payload
    );

    event SendMsg(
        uint16 chainId,
        uint16 funType,
        bytes lookup
    );

    event Revert(
        uint16 bridgeFunctionType,
        uint16 chainId,
        bytes srcAddress,
        uint256 nonce
    );

    //---------------------------------------------------------------------------
    // MODIFIERS
    modifier onlyVault() {
        require(msg.sender == address(vault), "MozBridge: Not vault");
        _;
    }
    modifier onlyController() {
        require(msg.sender == address(controller), "MozBridge: Not controller");
        _;
    }

    //---------------------------------------------------------------------------
    // CONSTRUCTOR
    constructor(
        address _lzEndpoint,
        uint16 _mainchainId
    ) {
        require(_mainchainId > 0, "MozBridge: Invalid chainID");
        require(_lzEndpoint != address(0x0), "MozBridge: _lzEndpoint cannot be 0x0");
        layerZeroEndpoint = ILayerZeroEndpoint(_lzEndpoint);
        mainChainId = _mainchainId;
    }

    //---------------------------------------------------------------------------
    // EXTERNAL FUNCTIONS

    function lzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) external override {
        require(msg.sender == address(layerZeroEndpoint), "MozBridge: only LayerZero endpoint can call lzReceive");
        require(
            _srcAddress.length == bridgeLookup[_srcChainId].length && keccak256(_srcAddress) == keccak256(bridgeLookup[_srcChainId]),
            "MozBridge: bridge does not match"
        );

        address from;
        assembly {
            from := mload(add(_srcAddress, 20))
        }

        uint16 functionType;
        assembly {
            functionType := mload(add(_payload, 32))
        }

        if (functionType == TYPE_REQUEST_SNAPSHOT) {
            require(_srcChainId == mainChainId, "MozBridge: message must come from main chain");
            ( ,uint256 _updateNum) = abi.decode(_payload, (uint16,  uint256));
            try vault.reportSnapshot(_srcChainId, _srcAddress, _nonce, _updateNum) {
            } catch {
                bytes memory payload = abi.encode(TYPE_SNAPSHOT_RETRY, _updateNum);
                vault.setRevertLookup(_srcChainId, _srcAddress, _nonce, payload);
                emit Revert(TYPE_SNAPSHOT_RETRY, _srcChainId, _srcAddress, _nonce);
            }
        } else if (functionType == TYPE_REPORT_SNAPSHOT) {
            ( , MozBridge.Snapshot memory _snapshot, uint256 _updateNum) = abi.decode(_payload, (uint16, MozBridge.Snapshot, uint256));
            controller.updateSnapshot(_srcChainId, _snapshot, _updateNum);
        } else if(functionType == TYPE_REQUEST_SETTLE) {
            require(_srcChainId == mainChainId, "MozBridge: message must come from main chain");
            ( , uint256 totalCoinMD, uint256 totalMLP, uint256 _updateNum) = abi.decode(_payload, (uint16, uint256, uint256, uint256));
            try vault.reportSettled(_srcChainId, _srcAddress, _nonce, totalCoinMD, totalMLP, _updateNum) {
            } catch {
                bytes memory payload = abi.encode(TYPE_SETTLE_RETRY, totalCoinMD, totalMLP, _updateNum);
                vault.setRevertLookup(_srcChainId, _srcAddress, _nonce, payload);
                emit Revert(TYPE_SETTLE_RETRY, _srcChainId, _srcAddress, _nonce);
            }
        } else if(functionType == TYPE_REPORT_SETTLE) {
            ( , uint256 _updateNum) = abi.decode(_payload, (uint16, uint256));
            controller.settleReport(_srcChainId, _updateNum);
        }else if (functionType == TYPE_STAKE_ASSETS) {
            ( , uint8 _pluginId, bytes memory __payload) = abi.decode(_payload, (uint16, uint8, bytes));
            vault.execute(_srcChainId, _srcAddress, _nonce, _pluginId, IPlugin.ActionType.Stake, __payload);
        } else if (functionType == TYPE_UNSTAKE_ASSETS) {
            ( , uint8 _pluginId, bytes memory __payload) = abi.decode(_payload, (uint16, uint8, bytes));
            vault.execute(_srcChainId, _srcAddress, _nonce, _pluginId, IPlugin.ActionType.Unstake, __payload);
        }

        emit ReceiveMsg(_srcChainId, from, functionType, _payload);
    }

    //------------------------------------CONFIGURATION------------------------------------
    
    // Set Local Vault
    function setVault(address _vault) external onlyOwner {
        require(_vault != address(0x0), "ERROR: Invaild address");
        vault = Vault(payable (_vault));
    }
    
    // Set Controller    
    function setController(address payable _controller) public onlyOwner {
        require(_controller != address(0), "ERROR: Invalid address");
        controller =  Controller(_controller);
    }

    //Set gas amount
    function setGasAmount(
        uint16 _chainId,
        uint16 _functionType,
        uint256 _gasAmount
    ) external onlyOwner {
        require(_functionType >= 1 && _functionType <= 6, "MozBridge: invalid _functionType");
        gasLookup[_chainId][_functionType] = _gasAmount;
    }

    // Set BridgeLookups
    function setBridge(uint16 _chainId, bytes calldata _bridgeAddress) external onlyOwner {
        require(_chainId > 0, "MozBridge: Set bridge error");
        bridgeLookup[_chainId] = _bridgeAddress;
    }

    // Clear the stored payload and resume
    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override onlyOwner {
        layerZeroEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    // set if use layerzero token
    function setUseLayerZeroToken(bool enable) external onlyOwner {
        useLayerZeroToken = enable;
    }

    // generic config for user Application
    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint256 _configType,
        bytes calldata _config
    ) external override onlyOwner {
        layerZeroEndpoint.setConfig(_version, _chainId, _configType, _config);
    }

    function setSendVersion(uint16 version) external override onlyOwner {
        layerZeroEndpoint.setSendVersion(version);
    }

    function setReceiveVersion(uint16 version) external override onlyOwner {
        layerZeroEndpoint.setReceiveVersion(version);
    }

    //---------------------------------LOCAL CHAIN FUNCTIONS--------------------------------

    // Send snapshot request to local chains (Only called on Mainchain)
    function requestSnapshot(uint16 _dstChainId, uint256 _updateNum, address payable _refundAddress ) external payable onlyController {
        require(_dstChainId > 0, "MozBridge: Invalid ChainId");
        require(_refundAddress != address(0x0), "MozBridge: Invalid address");
        
        bytes memory payload = abi.encode(TYPE_REQUEST_SNAPSHOT, _updateNum);
        LzTxObj memory lzTxObj = LzTxObj(0, 0, "0x");
        _call(_dstChainId, TYPE_REQUEST_SNAPSHOT, payable(_refundAddress), lzTxObj, payload);
    }

    // Report snapshot details to Controller (Olny called on Localchains)
    function reportSnapshot(
        MozBridge.Snapshot memory _snapshot,
        uint256 _updateNum,
        address payable _refundAddress
        // Vault.Snapshot memory _snapshot
    ) external payable onlyVault {
        bytes memory payload = abi.encode(TYPE_REPORT_SNAPSHOT, _snapshot, _updateNum);
        LzTxObj memory lzTxObj = LzTxObj(0, 0, "0x");
        _call(mainChainId, TYPE_REPORT_SNAPSHOT, payable(_refundAddress), lzTxObj, payload);
    }

    // Send settle request to local chains (Only called on Mainchain)
    function requestSettle(uint16 _dstChainId, uint256  totalCoinMD, uint256 totalMLP, uint256 _updateNum, address payable _refundAddress ) external payable onlyController {
        require(_dstChainId > 0, "MozBridge: Invalid ChainId");
        require(_refundAddress != address(0x0), "MozBridge: Invalid address");
        
        bytes memory payload = abi.encode(TYPE_REQUEST_SETTLE, totalCoinMD, totalMLP, _updateNum);
        LzTxObj memory lzTxObj = LzTxObj(0, 0, "0x");
        _call(_dstChainId, TYPE_REQUEST_SETTLE, payable(_refundAddress), lzTxObj, payload);
    }

    // Send settle report to Controller (Only called on Localchains)
    function reportSettled(uint256 _updateNum, address payable _refundAddress ) external payable onlyVault {
        require(_refundAddress != address(0x0), "MozBridge: Invalid address");
        bytes memory payload = abi.encode(TYPE_REPORT_SETTLE, _updateNum);
        LzTxObj memory lzTxObj = LzTxObj(0, 0, "0x");
        _call(mainChainId, TYPE_REPORT_SETTLE, payable(_refundAddress), lzTxObj, payload);

    }

    // Send the execute request to plugin.
    function requestExecute(uint16 _dstChainId, uint8 _pluginId, uint16 executeType, bytes memory _payload, address payable _refundAddress) external payable onlyController {
        require(_dstChainId > 0, "MozBridge: Invalid ChainId");
        require(_refundAddress != address(0x0), "MozBridge: Invalid address");
        bytes memory payload = abi.encode(executeType, _pluginId, _payload);
        LzTxObj memory lzTxObj = LzTxObj(0, 0, "0x");
        _call(_dstChainId, executeType, payable(_refundAddress), lzTxObj, payload);
    }

    // Get and return the snapshot of the local vault
    // Used to get the snapshot of main chain
    // Only used in main chain Bridge
    function takeSnapshot() external onlyController returns (Snapshot memory) {
        return vault.takeSnapshot();
    }

    // Settle the deposit and withdraw requests of the mainchain vault
    // Used to settle requests of main chain
    // Only used in main chain Bridge
    function setSettle(uint256  totalCoinMD, uint256 totalMLP) external onlyController {
        vault.settleRequests(totalCoinMD, totalMLP);
    }

    // Execute the action in mainchain vault
    // Used to execute actions on main chain
    function execute(uint8 _pluginId, IPlugin.ActionType _actionType, bytes memory _payload) external onlyController() {
        vault.execute(mainChainId, bridgeLookup[mainChainId], 0, _pluginId, _actionType, _payload);
    }
    
    //---------------------------------------------------------------------------
    // PUBLIC FUNCTIONS
    function quoteLayerZeroFee(
        uint16 _chainId,
        uint16 _msgType,
        LzTxObj memory _lzTxParams,
        bytes memory _payload
    ) public view returns (uint256 _nativeFee, uint256 _zroFee) {   
        bytes memory payload = "";
        if (_msgType == TYPE_REQUEST_SNAPSHOT) {
            payload = abi.encode(TYPE_REQUEST_SNAPSHOT, _payload);
        }
        else if (_msgType == TYPE_REPORT_SNAPSHOT) {
            payload = abi.encode(TYPE_REPORT_SNAPSHOT, _payload);
        }
        else if (_msgType == TYPE_REQUEST_SETTLE) {
            payload = abi.encode(TYPE_REQUEST_SETTLE, _payload);
        }
        else if (_msgType == TYPE_REPORT_SETTLE) {
            payload = abi.encode(TYPE_REPORT_SETTLE, _payload);
        }
        else if (_msgType == TYPE_STAKE_ASSETS) {
            payload = abi.encode(TYPE_STAKE_ASSETS, _payload);
        }
        else if (_msgType == TYPE_UNSTAKE_ASSETS) {
            payload = abi.encode(TYPE_UNSTAKE_ASSETS, _payload);
        }
        else {
            revert("MozBridge: unsupported function type");
        }
        
        bytes memory _adapterParams = _txParamBuilder(_chainId, _msgType, _lzTxParams);
        return layerZeroEndpoint.estimateFees(_chainId, address(this), payload, useLayerZeroToken, _adapterParams);
    }

    //---------------------------------------------------------------------------
    // INTERNAL FUNCTIONS
    function txParamBuilderType1(uint256 _gasAmount) internal pure returns (bytes memory) {
        uint16 txType = 1;
        return abi.encodePacked(txType, _gasAmount);
    }

    function txParamBuilderType2(
        uint256 _gasAmount,
        uint256 _dstNativeAmount,
        bytes memory _dstNativeAddr
    ) internal pure returns (bytes memory) {
        uint16 txType = 2;
        return abi.encodePacked(txType, _gasAmount, _dstNativeAmount, _dstNativeAddr);
    }

    function _txParamBuilder(
        uint16 _chainId,
        uint16 _type,
        LzTxObj memory _lzTxParams
    ) internal view returns (bytes memory) {
        bytes memory lzTxParam;
        address dstNativeAddr;
        {
            bytes memory dstNativeAddrBytes = _lzTxParams.dstNativeAddr;
            assembly {
                dstNativeAddr := mload(add(dstNativeAddrBytes, 20))
            }
        }

        uint256 totalGas = gasLookup[_chainId][_type] + _lzTxParams.dstGasForCall;
        if (_lzTxParams.dstNativeAmount > 0 && dstNativeAddr != address(0x0)) {
            lzTxParam = txParamBuilderType2(totalGas, _lzTxParams.dstNativeAmount, _lzTxParams.dstNativeAddr);
        } else {
            lzTxParam = txParamBuilderType1(totalGas);
        }

        return lzTxParam;
    }

    function _call(
        uint16 _dstChainId,
        uint16 _type,
        address payable _refundAddress,
        LzTxObj memory _lzTxParams,
        bytes memory _payload
    ) internal {
        require(bridgeLookup[_dstChainId].length > 0, "MozBridge: Invalid bridgeLookup");
        bytes memory lzTxParamBuilt = _txParamBuilder(_dstChainId, _type, _lzTxParams);
        layerZeroEndpoint.send{value: msg.value}(
            _dstChainId,
            bridgeLookup[_dstChainId],
            _payload,
            payable(_refundAddress),
            address(this),
            lzTxParamBuilt
        );
        emit SendMsg(_dstChainId, _type, bridgeLookup[_dstChainId]);
    }
}

