// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./WitnetV2.sol";

/// @title Witnet Request Board base data model. 
/// @author The Witnet Foundation.
abstract contract WitnetBytecodesData {
    
    bytes32 private constant _WITNET_BYTECODES_DATA_SLOTHASH =
        /* keccak256("io.witnet.bytecodes.data") */
        0x673359bdfd0124f9962355e7aed2d07d989b0d4bc4cbe2c94c295e0f81427dec;

    struct Storage {
        address base;
        address owner;
        address pendingOwner;
        
        Database db;
        uint256 totalDataProviders;
        // ...
    }

    struct RadonRequest {
        string[][] args;
        bytes32 aggregator;
        bytes32 radHash;
        WitnetV2.RadonDataTypes resultDataType;
        uint16 resultMaxSize;
        bytes32[] retrievals;
        bytes32 tally;
    }

    struct Database {
        mapping (uint256 => WitnetV2.DataProvider) providers;
        mapping (bytes32 => uint256) providersIndex;
        
        mapping (bytes32 => WitnetV2.RadonReducer) reducers;
        mapping (bytes32 => WitnetV2.RadonRetrieval) retrievals;
        mapping (bytes32 => WitnetV2.RadonSLA) slas;
        
        mapping (bytes32 => RadonRequest) requests;
        mapping (bytes32 => bytes32) rads;

        mapping (bytes32 => bytes) radsBytecode;
        mapping (bytes32 => bytes) slasBytecode;
    }

    constructor() {
        // auto-initialize upon deployment
        __bytecodes().base = address(this);
    }


    // ================================================================================================================
    // --- Internal state-modifying functions -------------------------------------------------------------------------
    
    /// @dev Returns storage pointer to contents of 'Storage' struct.
    function __bytecodes()
      internal pure
      returns (Storage storage _ptr)
    {
        assembly {
            _ptr.slot := _WITNET_BYTECODES_DATA_SLOTHASH
        }
    }

    /// @dev Returns storage pointer to contents of 'Database' struct.
    function __database()
      internal view
      returns (Database storage _ptr)
    {
        return __bytecodes().db;
    }

    function __requests(bytes32 _drRetrievalHash)
        internal view
        returns (RadonRequest storage _ptr)
    {
        return __database().requests[_drRetrievalHash];
    }
}
