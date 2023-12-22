// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.9;

import {AccessControl} from "./AccessControl.sol";
import {GenerateCallData} from "./generateCalldata.sol";

enum QueryType {
    TIMESTAMP,
    USER,
    ZERO,
    QUERY
}

// This object will allow the contract to query the parameter onChain
struct ParameterQuery {
    QueryType parameterType;
    bool isCachable;
    GetInfoCalldata queryCallData;
}

struct DirectoryMethodInfo {
    uint8 argc;
    bytes4 methodSelector;
    uint8[4] amountPositions;
    uint8[4] amountMinimumPositions;
}

struct CallInfo {
    address interactionAddress;
    address[] inputTokens;
    bytes callData;
    uint256 value;
}

struct GetInfoCalldata {
    bytes callData;
    uint8 position;
    Location location;
}

// We want to be able to get the location of the data query
enum Location {
    PoolAddress,
    InteractionAddress,
    QueryPoolAddress,
    QueryInteractionAddress
}

struct GetSpecificMethodInfo {
    GetInfoCalldata[] getInTokens;
    GetInfoCalldata[] getOutTokens;
}

struct TokenLengths {
    uint8 inTokens;
    uint8 outTokens;
}

struct SpecificMethodInfo {
    address interactionAddress;
    address[] inTokens;
    address[] outTokens;
}

struct ParameterQueryInput {
    ParameterQuery query;
    uint8 position;
}

struct ProtocolInput {
    DirectoryMethodInfo methodInfo;
    GetInfoCalldata[] inTokens;
    GetInfoCalldata[] outTokens;
    TokenLengths tokenLengths;
    address rawInteractionAddress;
    GetInfoCalldata interactionAddress;
    ParameterQueryInput[] parameterQuery;
}

uint256 constant BLOCK_TIME_DELTA = 300; // 5min delta

contract Directory is GenerateCallData, AccessControl {
    address constant nativeToken = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    /// Here we want to get the mthod Info for each pool (different)
    // Mapping protocol name + method name to DirectoryMethodInfo
    mapping(string => mapping(string => DirectoryMethodInfo)) methods;

    // This object will allow to get the inTokens and outTokens for a poolAddress inside a certain protocol
    mapping(string => mapping(string => GetSpecificMethodInfo)) interactionTokens;
    mapping(string => mapping(string => TokenLengths)) tokenLengths;

    // Here we want to get the specific arguments for the called address (pool dependent)
    mapping(string => mapping(string => mapping(uint256 => ParameterQuery))) specificCallInfo;
    // The position in the argv array for that parameter
    mapping(string => mapping(string => uint8[])) specificCallInfoArgv;

    /// Here we want to get the interaction address from the pool address
    mapping(string => mapping(string => GetInfoCalldata)) interactionAddressInfo;
    mapping(string => mapping(string => address)) rawInteractionAddress;

    // We cache all the information we need from each call
    // The first call will cost something but the subsequent one will be much cheaper
    // For now, we only cache addresses
    // Keys are the following
    // (protocol, methoType, pool, infoId)
    mapping(string => mapping(string => mapping(bytes32 => bytes32))) public cachedInfo;

    function accessCache(string calldata protocol, string calldata methodType, bytes32 cacheKey)
        public
        view
        returns (bytes32 cache)
    {
        cache = cachedInfo[protocol][methodType][cacheKey];
    }

    function addressToBytes32(address a) public pure returns (bytes32) {
        return bytes32(uint256(uint160(a)));
    }

    function bytes32ToAddress(bytes32 b) public pure returns (address) {
        return address(uint160(uint256(b)));
    }

    /* 
        MODIFIERS
    */

    modifier onlyOwner() {
        _checkRole(DEFAULT_ADMIN_ROLE);
        _;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// ============ Errors ============
    error NullCacheSet();
    error InvalidInteractionAddressConfig();
    error ProtocolNotRegistered();
    error InformationQueryFailed();

    /*
    constructor(bool setup){
    if(setup){
    // We start by saving the protocol info, for tests
     	setupYEARN();
     	setupVELODROME();
     	setupCURVE();
     	setupSTARGATE();
     }
    }
    */

    /* ******************************************* 	*/
    /*												*/
    /*  Admin only functions to add new protocols 	*/
    /*												*/
    /* ******************************************* 	*/

    /// @notice Registers a new protocol method in the directory
    /// @notice All the method information should be registered in a single call
    /// @notice This allows does not allow adding pool specific information
    ///
    /// @param protocol Designates the protocol that is being registered. E.g "velodrome/v0".
    ///        This is the main id of the registered method
    /// @param methodType Designates the method Type being integrated. E.g "deposit".
    ///        This is the secondary id of the registered method
    /// @param _input All the data that will be registered in the directory
    function registerMethod(string calldata protocol, string calldata methodType, ProtocolInput calldata _input)
        external
        onlyOwner
    {
        // Method Related Info
        methods[protocol][methodType] = _input.methodInfo;

        // In and Out tokens
        uint256 inTokenLength = _input.inTokens.length;
        delete interactionTokens[protocol][methodType].getInTokens;
        for (uint256 i; i < inTokenLength; ++i) {
            interactionTokens[protocol][methodType].getInTokens.push(_input.inTokens[i]);
        }
        uint256 outTokenLength = _input.outTokens.length;
        delete interactionTokens[protocol][methodType].getOutTokens;
        for (uint256 i; i < outTokenLength; ++i) {
            interactionTokens[protocol][methodType].getOutTokens.push(_input.outTokens[i]);
        }
        tokenLengths[protocol][methodType] = _input.tokenLengths;

        // Interaction Address
        rawInteractionAddress[protocol][methodType] = _input.rawInteractionAddress;
        interactionAddressInfo[protocol][methodType] = _input.interactionAddress;
        if (
            _input.interactionAddress.location == Location.InteractionAddress
                || _input.interactionAddress.location == Location.QueryInteractionAddress
        ) {
            revert InvalidInteractionAddressConfig();
        }

        // Other call arguments location
        uint256 parameterQueryLength = _input.parameterQuery.length;

        delete specificCallInfoArgv[protocol][methodType];
        for (uint256 i; i < parameterQueryLength; ++i) {
            specificCallInfo[protocol][methodType][i] = _input.parameterQuery[i].query;
            specificCallInfoArgv[protocol][methodType].push(_input.parameterQuery[i].position);
        }
    }

    function isMethodRegistered(string calldata protocol, string calldata methodType) public view returns (bool) {
        bytes4 methodSelector = methods[protocol][methodType].methodSelector;
        return methodSelector != bytes4(0);
    }

    /// @notice Registers a cache entry in the directory
    /// @notice This cache is pool specific and will be used instead of the queried information if present.
    ///	@dev Caching reduces gas usage for the following calls
    /// @param protocol Designates the protocol the pool belongs to. e.g "curve/v2"
    /// @param methodType Designates the method Type for which the information is registered e.g. "deposit"
    /// @param key The cache key that should be set
    /// 	Here are the different key types that can be used :
    /// 		- keccak256(abi.encode(poolAddress, "input",  uint256(n))) for the nth input token
    /// 		- keccak256(abi.encode(poolAddress, "output",  uint256(n))) for the nth output token
    ///			- keccak256(abi.encode(poolAddress, "interaction")) for the interaction address associated with the pool
    ///			- keccak256(abi.encode(poolAddress, "queries", uint256(n))) for the nth element in specificCallInfo
    /// @param value The cache value that should be set
    /// @dev Here are the two use cases for this function
    ///		1. Set a cache value so that no user bears the gas price associated with
    ///        getting the value and setting the cache
    ///		2. Register a pool specific value that is not queryable on chain (e.g. cirve investing addresses on ethereum)
    function setCache(string calldata protocol, string calldata methodType, bytes32 key, bytes32 value)
        external
        onlyOwner
    {
        if (value == bytes32(uint256(0))) revert NullCacheSet();
        cachedInfo[protocol][methodType][key] = value;
    }

    function resetCache(string calldata protocol, string calldata methodType, bytes32 key) external onlyOwner {
        cachedInfo[protocol][methodType][key] = bytes32(uint256(0));
    }

    /// @notice Queries the interaction address for a specific poolAddress
    /// @param poolAddress The poolAddress for which you want to query the interaction Address
    /// @param protocol designates the protocol the pool belongs to. e.g "curve/v2"
    /// @param methodType designates the method Type for which the information is registered e.g. "deposit"
    /// @dev To query the interaction address, this function :
    ///		1. Uses the cached value if any
    ///		2. Uses the interaction address registered with the protocol and methodType if any
    ///		3. Queries the interaction address using the GetInfoCalldata object associated with the protocol and method
    function _getInteractionAddress(address poolAddress, string calldata protocol, string calldata methodType)
        internal
        returns (address interactionAddress)
    {
        if (accessCache(protocol, methodType, keccak256(abi.encode(poolAddress, "interaction"))) != bytes32(0)) {
            interactionAddress =
                bytes32ToAddress(accessCache(protocol, methodType, keccak256(abi.encode(poolAddress, "interaction"))));
        } else {
            if (rawInteractionAddress[protocol][methodType] != address(0)) {
                interactionAddress = rawInteractionAddress[protocol][methodType];
            } else {
                interactionAddress =
                    bytes32ToAddress(_getInfo(poolAddress, address(0), interactionAddressInfo[protocol][methodType]));
            }
            cachedInfo[protocol][methodType][keccak256(abi.encode(poolAddress, "interaction"))] =
                addressToBytes32(interactionAddress);
        }
    }

    /// @notice Queries the input tokens for a specific poolAddress
    /// @param poolAddress The poolAddress for which you want to query the input tokens
    /// @param protocol Designates the protocol the pool belongs to. e.g "curve/v2"
    /// @param methodType Designates the method Type for the interaction e.g. "deposit"
    /// @dev To query the interaction address the contract, in order :
    ///		1. Uses the cached value if any
    ///		2. Queries the input tokens using the GetInfoCalldata objects associated with the protocol and method
    function getInputTokens(address poolAddress, string calldata protocol, string calldata methodType)
        public
        returns (address[] memory)
    {
        if (accessCache(protocol, methodType, keccak256(abi.encode(poolAddress, "input", uint256(0)))) != bytes32(0)) {
            address[] memory tokens = new address[](tokenLengths[protocol][methodType].inTokens);
            for (uint256 i; i < tokenLengths[protocol][methodType].inTokens; ++i) {
                tokens[i] =
                    bytes32ToAddress(accessCache(protocol, methodType, keccak256(abi.encode(poolAddress, "input", i))));
            }
            return tokens;
        }
        return
            getTokens(poolAddress, interactionTokens[protocol][methodType].getInTokens, protocol, methodType, "input");
    }

    /// @notice Queries the output tokens for a specific poolAddress
    /// @param poolAddress The poolAddress for which you want to query the output tokens
    /// @param protocol Designates the protocol the pool belongs to. e.g "curve/v2"
    /// @param methodType Designates the method Type for the interaction e.g. "deposit"
    /// @dev To query the output tokens, this function :
    ///		1. Uses the cached value if any
    ///		2. Queries the output tokens using the GetInfoCalldata objects associated with the protocol and method
    function getOutputTokens(address poolAddress, string calldata protocol, string calldata methodType)
        external
        returns (address[] memory)
    {
        if (accessCache(protocol, methodType, keccak256(abi.encode(poolAddress, "output", uint256(0)))) != bytes32(0)) {
            address[] memory tokens = new address[](tokenLengths[protocol][methodType].outTokens);
            for (uint256 i; i < tokenLengths[protocol][methodType].outTokens; ++i) {
                tokens[i] =
                    bytes32ToAddress(accessCache(protocol, methodType, keccak256(abi.encode(poolAddress, "output", i))));
            }
            return tokens;
        }
        return
            getTokens(poolAddress, interactionTokens[protocol][methodType].getOutTokens, protocol, methodType, "output");
    }

    function getTokens(
        address poolAddress,
        GetInfoCalldata[] memory getTokensInfo,
        string calldata protocol,
        string calldata methodType,
        string memory tokenType
    ) internal returns (address[] memory) {
        uint256 n = getTokensInfo.length;
        address[] memory tokens = new address[](n);
        address interactionAddress = address(0);

        for (uint256 i; i < n; ++i) {
            if (
                interactionAddress == address(0)
                    && (
                        getTokensInfo[i].location == Location.InteractionAddress
                            || getTokensInfo[i].location == Location.QueryInteractionAddress
                    )
            ) {
                interactionAddress = _getInteractionAddress(poolAddress, protocol, methodType);
            }
            bytes32 tokenBytes = _getInfo(poolAddress, interactionAddress, getTokensInfo[i]);
            tokens[i] = bytes32ToAddress(tokenBytes);
            cachedInfo[protocol][methodType][keccak256(abi.encode(poolAddress, tokenType, i))] = tokenBytes;
        }
        return tokens;
    }

    /// @notice Queries information on-chain using the directory data structure
    /// @param poolAddress The poolAddress for which you want to query data
    /// @param interactionAddress The interactionAddress of the pool for the current method
    /// @param info Information on how to query data from an address
    /// @dev Querying an info checks in order :
    /// 	1. If the location is Location.PoolAddress, it returns the poolAddress
    ///		2. If the location is Location.InteractionAddress, it returns the interactionAddress
    ///		3. Else, we conduct a full on-chain query to get the info result
    ///			a. We start by getting the queryAddress.
    ///				It's either the poolAddress/interactionAddress depending to Location
    ///			b. We call the read using the provided callData
    ///			c. We return the 32 bytes information at the info.position location.
    function _getInfo(address poolAddress, address interactionAddress, GetInfoCalldata memory info)
        internal
        returns (bytes32 data)
    {
        if (info.location == Location.PoolAddress) {
            return addressToBytes32(poolAddress);
        } else if (info.location == Location.InteractionAddress) {
            return addressToBytes32(interactionAddress);
        } else {
            address queryAddress;
            if (info.location == Location.QueryPoolAddress) {
                queryAddress = poolAddress;
            } else if (info.location == Location.QueryInteractionAddress) {
                queryAddress = interactionAddress;
            }

            (bool success, bytes memory result) = queryAddress.call(info.callData);

            uint256 tokenPosition = info.position;
            assembly {
                data := mload(add(result, mul(0x20, add(tokenPosition, 1))))
            }
            if (!success) revert InformationQueryFailed();
        }
    }

    /// @notice Fills the call argument array with the inputed amounts and minimumAmounts
    /// @param protocol designates the protocol the pool belongs to. e.g "curve/v2"
    /// @param methodType designates the method Type for which the information is registered e.g. "deposit"
    /// @param callInfo argument array that will be filled. Its length won't change.
    /// @param amounts Array of amounts that need to be provided to the interaction method.
    ///			This should have the same length as the methods[protocol][methodType].amountPositions
    /// @param amountsMinimum Array of minimum amounts that need to be provided to the interaction method.
    ///			This should have the same length as the methods[protocol][methodType].amountMinimumPositions
    function _fillAmountPositions(
        string calldata protocol,
        string calldata methodType,
        bytes32[] memory callInfo,
        uint256[] memory amounts,
        uint256[] memory amountsMinimum
    ) internal view returns (bytes32[] memory) {
        // We add the amount with their respective amountPositions and amountMinimumPositions
        // These array are the same length than the inTokens and are mandatory in the calldata
        uint256 amountPositionsLength = methods[protocol][methodType].amountPositions.length;
        for (uint256 i; i < amountPositionsLength; ++i) {
            if (methods[protocol][methodType].amountPositions[i] != type(uint8).max) {
                callInfo[methods[protocol][methodType].amountPositions[i]] = bytes32(amounts[i]);
            }
        }
        uint256 amountMinimumPositionsLength = methods[protocol][methodType].amountMinimumPositions.length;
        for (uint256 i; i < amountMinimumPositionsLength; ++i) {
            if (methods[protocol][methodType].amountMinimumPositions[i] != type(uint8).max) {
                callInfo[methods[protocol][methodType].amountMinimumPositions[i]] = bytes32(amountsMinimum[i]);
            }
        }
        return callInfo;
    }

    /// @notice Generates the method arguments that need to be queried (outside of amounts)
    /// @param protocol designates the protocol the pool belongs to. e.g "curve/v2"
    /// @param methodType designates the method Type for which the information is registered e.g. "deposit"
    /// @param poolAddress the address of the pool that is being interacted with
    /// @param callInfo argument array that will be filled with on-chain info. Its length won't change.
    /// @param receiver Address of the receiver of the operation if needed in the method arguments
    /// @dev This function can populate 3 types of data :
    ///		1. The current timestamp
    ///		2. The receiver of the interaction call
    ///		3. Any type of on-chain data, queryable with only one call from either
    /// 		a. The pool address
    ///			b. The interactionaddress
    ///			c. A raw address that only depends on the protocol and method type
    function generateOnChainArgs(
        string calldata protocol,
        string calldata methodType,
        address poolAddress,
        bytes32[] memory callInfo,
        address receiver
    ) internal returns (bytes32[] memory) {
        uint256 parameterQueryLength = specificCallInfoArgv[protocol][methodType].length;
        for (uint256 i; i < parameterQueryLength; ++i) {
            // First we try to get the call info from the cache

            bytes32 data;
            if (accessCache(protocol, methodType, keccak256(abi.encode(poolAddress, "queries", i))) != bytes32(0)) {
                data = accessCache(protocol, methodType, keccak256(abi.encode(poolAddress, "queries", i)));
                // We put it directly as bytes32 in our object
            } else {
                // If it's not in the cache, we load it as usual
                ParameterQuery memory parameterQuery = specificCallInfo[protocol][methodType][i];
                //We start by selecting the query type
                if (parameterQuery.parameterType == QueryType.TIMESTAMP) {
                    data = bytes32(block.timestamp + BLOCK_TIME_DELTA);
                } else if (parameterQuery.parameterType == QueryType.USER) {
                    data = addressToBytes32(receiver);
                } else if (parameterQuery.parameterType == QueryType.ZERO) {
                    data = bytes32(uint256(0));
                } else {
                    data = _getInfo(
                        poolAddress,
                        _getInteractionAddress(poolAddress, protocol, methodType),
                        parameterQuery.queryCallData
                    );
                    // We cache it if needed
                    if (parameterQuery.isCachable) {
                        cachedInfo[protocol][methodType][keccak256(abi.encode(poolAddress, "queries", i))] = data;
                    }
                }
            }
            callInfo[specificCallInfoArgv[protocol][methodType][i]] = data;
        }
        return callInfo;
    }

    /// @notice Generates address, calldata, value and input Tokens needed for interacting with a protocol.
    /// @notice This function allows protocols to integrate with multiple lending and AMM protocols with a
    ///         common contract interface
    /// @notice This aims at reducing dev time and simplify integration of different protocols
    /// @param poolAddress pool the user wants to interact with
    /// @param protocol protocol name the user wants to interact with. This protocol name should match information
    ///        that is stored in the contract
    /// @param methodType Type of operation the user wants to conduct on the protocol. e.g. "deposit"
    /// @param amounts Array of amounts that the user wants to provide to the protocol. e.g. In the case of
    ///        lending protocols, this array will have only one element
    /// @param amountsMinimum Array of minimum amounts the user wants to provide to the protocol (especially for AMMs)
    /// @param receiver Receiver of the interaction. This parameter is only used by the protocol that the user wants
    ///        to interact with
    function onChainAPI(
        address poolAddress,
        string calldata protocol,
        string calldata methodType,
        uint256[] memory amounts, // not changed to calldata, because there are too much local variables
        uint256[] memory amountsMinimum, // not changed to calldata, because there are too much local variables
        address receiver
    ) external returns (CallInfo memory callInfo) {
        //1. We get the method that is registered in the protocol
        callInfo.interactionAddress = _getInteractionAddress(poolAddress, protocol, methodType);
        if (callInfo.interactionAddress == address(0)) revert ProtocolNotRegistered();

        // 2. We need the inputTokens
        callInfo.inputTokens = getInputTokens(poolAddress, protocol, methodType);

        // 3. We need to generate the calldata
        // a. We need to know how much args there is
        bytes32[] memory callArgs = new bytes32[](methods[protocol][methodType].argc);
        {
            // b. We need to fill that array with the constant calldata (on-chain)
            callArgs = generateOnChainArgs(protocol, methodType, poolAddress, callArgs, receiver);
            // c. We need to fill that array with the amounts calldata (from arguments)
            callArgs = _fillAmountPositions(protocol, methodType, callArgs, amounts, amountsMinimum);
        }

        // 4. We need to make sure we send the right value in the transaction
        uint256 inputTokenLength = callInfo.inputTokens.length;
        for (uint256 i; i < inputTokenLength; ++i) {
            if (callInfo.inputTokens[i] == nativeToken) {
                callInfo.value += amounts[i];
            }
        }
        callInfo.callData = _generateCalldataFromBytes(methods[protocol][methodType].methodSelector, callArgs);
    }
}

