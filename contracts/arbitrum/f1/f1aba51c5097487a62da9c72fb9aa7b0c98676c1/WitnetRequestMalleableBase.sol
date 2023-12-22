// SPDX-License-Identifier: MIT

pragma solidity >=0.7.0 <0.9.0;

import "./Witnet.sol";

import "./Clonable.sol";
import "./access_Ownable.sol";
import "./Proxiable.sol";

abstract contract WitnetRequestMalleableBase
    is
        IWitnetRequest,
        Clonable,
        Ownable,
        Proxiable
{   
    using Witnet for *;

    event WitnessingParamsChanged(
        address indexed by,
        uint8 numWitnesses,
        uint8 minWitnessingConsensus,
        uint64 witnssingCollateral,
        uint64 witnessingReward,
        uint64 witnessingUnitaryFee
    );

    struct WitnetRequestMalleableBaseContext {
        /// Contract owner address.
        address owner;
        /// Immutable bytecode template.
        bytes template;
        /// Current request bytecode.
        bytes bytecode;
        /// Current request hash.
        bytes32 hash;
        /// Current request witnessing params.
        WitnetRequestWitnessingParams params;
    }

    struct WitnetRequestWitnessingParams {
        /// Number of witnesses required to be involved for solving this Witnet Data Request.
        uint8 numWitnesses;

        /// Threshold percentage for aborting resolution of a request if the witnessing nodes did not arrive to a broad consensus.
        uint8 minWitnessingConsensus;

        /// Amount of nanowits that a witness solving the request will be required to collateralize in the commitment transaction.
        uint64 witnessingCollateral;

        /// Amount of nanowits that every request-solving witness will be rewarded with.
        uint64 witnessingReward;

        /// Amount of nanowits that will be earned by Witnet miners for each each valid commit/reveal transaction they include in a block.
        uint64 witnessingUnitaryFee;
    }

    /// Returns current Witnet Data Request bytecode, encoded using Protocol Buffers.
    function bytecode() external view override returns (bytes memory) {
        return __storage().bytecode;
    }

    /// Returns SHA256 hash of current Witnet Data Request bytecode.
    function hash() external view override returns (bytes32) {
        return __storage().hash;
    }

    /// Sets amount of nanowits that a witness solving the request will be required to collateralize in the commitment transaction.
    function setWitnessingCollateral(uint64 _witnessingCollateral)
        public
        virtual
        onlyOwner
    {
        WitnetRequestWitnessingParams storage _params = __storage().params;
        _params.witnessingCollateral = _witnessingCollateral;
        _malleateBytecode(
            _params.numWitnesses,
            _params.minWitnessingConsensus,
            _witnessingCollateral,
            _params.witnessingReward,
            _params.witnessingUnitaryFee
        );
    }

    /// Specifies how much you want to pay for rewarding each of the Witnet nodes.
    /// @param _witnessingReward Amount of nanowits that every request-solving witness will be rewarded with.
    /// @param _witnessingUnitaryFee Amount of nanowits that will be earned by Witnet miners for each each valid 
    /// commit/reveal transaction they include in a block.
    function setWitnessingFees(uint64 _witnessingReward, uint64 _witnessingUnitaryFee)
        public
        virtual
        onlyOwner
    {
        WitnetRequestWitnessingParams storage _params = __storage().params;
        _params.witnessingReward = _witnessingReward;
        _params.witnessingUnitaryFee = _witnessingUnitaryFee;
        _malleateBytecode(
            _params.numWitnesses,
            _params.minWitnessingConsensus,
            _params.witnessingCollateral,
            _witnessingReward,
            _witnessingUnitaryFee
        );
    }

    /// Sets how many Witnet nodes will be "hired" for resolving the request.
    /// @param _numWitnesses Number of witnesses required to be involved for solving this Witnet Data Request.
    /// @param _minWitnessingConsensus Threshold percentage for aborting resolution of a request if the witnessing 
    /// nodes did not arrive to a broad consensus.
    function setWitnessingQuorum(uint8 _numWitnesses, uint8 _minWitnessingConsensus)
        public
        virtual
        onlyOwner
    {
        WitnetRequestWitnessingParams storage _params = __storage().params;
        _params.numWitnesses = _numWitnesses;
        _params.minWitnessingConsensus = _minWitnessingConsensus;
        _malleateBytecode(
            _numWitnesses,
            _minWitnessingConsensus,
            _params.witnessingCollateral,
            _params.witnessingReward,
            _params.witnessingUnitaryFee
        );
    }

    /// Returns immutable template bytecode: actual CBOR-encoded data request at the Witnet protocol
    /// level, including no witnessing parameters at all.
    function template()
        external view
        returns (bytes memory)
    {
        return __storage().template;
    }

    /// Returns total amount of nanowits that witnessing nodes will need to collateralize all together.
    function totalWitnessingCollateral()
        external view
        returns (uint128)
    {
        WitnetRequestWitnessingParams storage _params = __storage().params;
        return _params.numWitnesses * _params.witnessingCollateral;
    }

    /// Returns total amount of nanowits that will have to be paid in total for this request to be solved.
    function totalWitnessingFee()
        external view
        returns (uint128)
    {
        WitnetRequestWitnessingParams storage _params = __storage().params;
        return _params.numWitnesses * (2 * _params.witnessingUnitaryFee + _params.witnessingReward);
    }

    /// Returns witnessing parameters of current Witnet Data Request.
    function witnessingParams()
        external view
        returns (WitnetRequestWitnessingParams memory)
    {
        return __storage().params;
    }


    // ================================================================================================================
    // --- 'Clonable' extension ---------------------------------------------------------------------------------------

    /// Deploys and returns the address of a minimal proxy clone that replicates contract
    /// behaviour while using its own EVM storage.
    /// @dev This function should always provide a new address, no matter how many times 
    /// @dev is actually called from the same `msg.sender`.
    /// @dev Ownership of new clone is transferred to the caller.
    function clone()
        virtual public
        wasInitialized
        returns (WitnetRequestMalleableBase)
    {
        return _afterCloning(_clone());
    }

    /// Deploys and returns the address of a minimal proxy clone that replicates contract 
    /// behaviour while using its own EVM storage.
    /// @dev This function uses the CREATE2 opcode and a `_salt` to deterministically deploy
    /// @dev the clone. Using the same `_salt` multiple time will revert, since
    /// @dev no contract can be deployed more than once at the same address.
    /// @dev Ownership of new clone is transferred to the caller.
    function cloneDeterministic(bytes32 _salt)
        virtual public
        wasInitialized
        returns (WitnetRequestMalleableBase)
    {
        return _afterCloning(_cloneDeterministic(_salt));
    }

    /// @notice Initializes a cloned instance. 
    /// @dev Every cloned instance can only get initialized once.
    function initializeClone(bytes memory _initData)
        virtual external
        initializer // => ensure a cloned instance can only be initialized once
        onlyDelegateCalls // => this method can only be called upon cloned instances
    {
        _initialize(_initData);
    }

    /// @notice Tells whether this instance has been initialized.
    function initialized()
        override 
        public view
        returns (bool)
    {
        return __storage().template.length > 0;
    }


    // ================================================================================================================
    // --- 'Ownable' overriden functions ------------------------------------------------------------------------------

    /// Returns the address of the current owner.
    function owner()
        public view
        virtual override
        returns (address)
    {
        return __storage().owner;
    }

    /// @dev Transfers ownership of the contract to a new account (`newOwner`).
    function _transferOwnership(address newOwner)
        internal
        virtual override
    {
        address oldOwner = __storage().owner;
        __storage().owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }


    // ================================================================================================================
    // --- 'Proxiable 'overriden functions ----------------------------------------------------------------------------

    /// @dev Complying with EIP-1822: Universal Upgradeable Proxy Standard (UUPS)
    /// @dev See https://eips.ethereum.org/EIPS/eip-1822.
    function proxiableUUID()
        external pure
        virtual override
        returns (bytes32)
    {
        return (
            /* keccak256("io.witnet.requests.malleable") */
            0x851d0a92a3ad30295bef33afc69d6874779826b7789386b336e22621365ed2c2
        );
    }


    // ================================================================================================================
    // --- INTERNAL FUNCTIONS -----------------------------------------------------------------------------------------    

    function _afterCloning(address _newInstance)
        virtual internal
        returns (WitnetRequestMalleableBase)
    {
        WitnetRequestMalleableBase(_newInstance).initializeClone(__storage().template);
        Ownable(address(_newInstance)).transferOwnership(msg.sender);
        return WitnetRequestMalleableBase(_newInstance);
    }

    /// @dev Initializes witnessing params and template bytecode. 
    function _initialize(bytes memory _template)
        virtual internal
    {
        _transferOwnership(_msgSender());

        assert(_template.length > 0);
        __storage().template = _template;

        WitnetRequestWitnessingParams storage _params = __storage().params;
        _params.numWitnesses = 7;
        _params.minWitnessingConsensus = 51;
        _params.witnessingCollateral = 15 * 10 ** 9;  // 15 WIT
        _params.witnessingReward = 15 * 10 ** 7;      // 150 mWIT
        _params.witnessingUnitaryFee = 10 ** 7; // 10 mWIT
        
        _malleateBytecode(
            _params.numWitnesses,
            _params.minWitnessingConsensus,
            _params.witnessingCollateral,
            _params.witnessingReward,
            _params.witnessingUnitaryFee
        );
    }

    /// @dev Serializes new `bytecode` by combining immutable template with given parameters.
    function _malleateBytecode(
            uint8 _numWitnesses,
            uint8 _minWitnessingConsensus,
            uint64 _witnessingCollateral,
            uint64 _witnessingReward,
            uint64 _witnessingUnitaryFee
        )
        internal
        virtual
    {
        require(
            _witnessingReward > 0,
            "WitnetRequestMalleableBase: no reward"
        );
        require(
            _numWitnesses >= 1 && _numWitnesses <= 127,
            "WitnetRequestMalleableBase: number of witnesses out of range"
        );
        require(
            _minWitnessingConsensus >= 51 && _minWitnessingConsensus <= 99,
            "WitnetRequestMalleableBase: witnessing consensus out of range"
        );
        require(
            _witnessingCollateral >= 10 ** 9,
            "WitnetRequestMalleableBase: witness collateral below 1 WIT"
        );

        __storage().bytecode = abi.encodePacked(
            __storage().template,
            _uint64varint(bytes1(0x10), _witnessingReward),
            _uint8varint(bytes1(0x18), _numWitnesses),
            _uint64varint(0x20, _witnessingUnitaryFee),
            _uint8varint(0x28, _minWitnessingConsensus),
            _uint64varint(0x30, _witnessingCollateral)
        );
        __storage().hash = __storage().bytecode.hash();
        emit WitnessingParamsChanged(
            msg.sender,
            _numWitnesses,
            _minWitnessingConsensus,
            _witnessingCollateral,
            _witnessingReward,
            _witnessingUnitaryFee
        );
    }

    /// @dev Returns pointer to storage slot where State struct is located.
    function __storage()
        internal pure
        virtual
        returns (WitnetRequestMalleableBaseContext storage _ptr)
    {
        assembly {
            _ptr.slot :=
                /* keccak256("io.witnet.requests.malleable.context") */
                0x375930152e1d0d102998be6e496b0cee86c9ecd0efef01014ecff169b17dfba7
        }
    }

    /// @dev Encode uint64 into tagged varint.
    /// @dev See https://developers.google.com/protocol-buffers/docs/encoding#varints.
    /// @param t Tag
    /// @param n Number
    /// @return Marshaled bytes
    function _uint64varint(bytes1 t, uint64 n)
        internal pure
        returns (bytes memory)
    {
        // Count the number of groups of 7 bits
        // We need this pre-processing step since Solidity doesn't allow dynamic memory resizing
        uint64 tmp = n;
        uint64 numBytes = 2;
        while (tmp > 0x7F) {
            tmp = tmp >> 7;
            numBytes += 1;
        }
        bytes memory buf = new bytes(numBytes);
        tmp = n;
        buf[0] = t;
        for (uint64 i = 1; i < numBytes; i++) {
            // Set the first bit in the byte for each group of 7 bits
            buf[i] = bytes1(0x80 | uint8(tmp & 0x7F));
            tmp = tmp >> 7;
        }
        // Unset the first bit of the last byte
        buf[numBytes - 1] &= 0x7F;
        return buf;
    }

    /// @dev Encode uint8 into tagged varint.
    /// @param t Tag
    /// @param n Number
    /// @return Marshaled bytes
    function _uint8varint(bytes1 t, uint8 n)
        internal pure
        returns (bytes memory)
    {
        return _uint64varint(t, uint64(n));
    }
}

