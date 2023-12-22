// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./BLS.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { IDepositContract } from "./IDepositContract.sol";
import { Ownable2Step } from "./Ownable2Step.sol";
import "./CommonError.sol";

/// @title VRF Generator Contract
/// @author Supra Developer
/// @notice This contract will generate random number based on the router contract request
/// @dev All function calls are currently implemented without side effects

contract SupraGeneratorContract is ReentrancyGuard, Ownable2Step {

    /// @dev Public key
    uint[4] public publicKey;

    /// @dev Domain
    bytes32 public domain;

    /// @dev Address of VRF Router contract
    address internal supraRouterContract;

    ///@dev Address of deposit contract
    address internal depositContract;
    IDepositContract public _depositContract;

    /// @dev BlockNumber
    uint256 internal blockNum = 0;

    /// @dev Instance Identification Number
    uint256 public instanceId;

    /// @dev A mapping that will keep track of all the nonces used, true means used and false means not used
    mapping(uint256 => bool) internal nonceUsed;

    /// @dev A mapping that will keep track of all the whitelisted free nodes
    mapping(address => bool) internal isFreeNodeWhitelisted;

    /// @notice It will put the logs for the Generated request with necessary parameters
    /// @dev This event will be emitted when random number request generated
    /// @param nonce nonce is an incremental counter which is associated with request
    /// @param instanceId Instance Identification Number
    /// @param callerContract Contract address from which request has been generated
    /// @param functionName Function which we have to callback to fulfill request
    /// @param rngCount Number of random numbers requested
    /// @param numConfirmations Number of Confirmations
    /// @param clientSeed Client seed is used to add extra randomness
    /// @param clientWalletAddress is the wallet to which the request is associated
    event RequestGenerated(uint256 nonce, uint256 instanceId, address callerContract, string functionName, uint8 rngCount, uint256 numConfirmations, uint256 clientSeed, address clientWalletAddress);

    /// @notice To put log regarding updation of Public key
    /// @dev This event will be emmitted in whenever there is a request to update Public Key
    /// @param _timestamp epoch time when Public key has been updated
    event PublicKeyUpdated(uint256 _timestamp);

    /// @notice It will put log for the nonce value for which request has been fulfilled
    /// @dev It will be emitted when callback to the Router contract has been made
    /// @param nonce nonce is an incremental counter which is associated with request
    /// @param clientWalletAddress is the address through which the request is generated and the nonce is associated
    event NonceProcessed(uint256 nonce, address clientWalletAddress, uint256 timestamp);

    /// @dev when caller is not supra router
    error RouterOnly();

    /// @dev when free node is not whitelisted
    error FreeNodeNotWhitelisted();

    /// @dev when free node is already whitelisted
    error FreeNodeAlreadyWhitelisted();

    /// @dev when a nonce has already been used
    error NonceUsed();

    /// @dev when client has insufficient funds
    error InsufficientFunds();

    /// @dev When parameters do not match signed message
    error ParamsSignedMessageMismatch();

    /// @dev When signature verification fails
    error SigVerifyFailed();

    /// @dev when BLS precompile call fails
    error PrecompileCallFailed();

    /// @dev when BLS signature is invalid
    error InvalidSig();

    constructor(bytes32 _domain, address _supraRouterContract, uint[4] memory _publicKey, uint256 _instanceId) {
        publicKey = _publicKey;
        domain = _domain;
        supraRouterContract = _supraRouterContract;
        instanceId = _instanceId;
    }

    /// @notice This function is used to generate random number request
    /// @dev This function will be called from router contract which is for the random number generation request
    /// @param _nonce nonce is an incremental counter which is associated with request
    /// @param _callerContract Actual client contract address from which request has been generated
    /// @param _functionName A combination of a function and the types of parameters it takes, combined together as a string with no spaces
    /// @param _rngCount Number of random numbers requested
    /// @param _numConfirmations Number of Confirmations
    /// @param _clientSeed Use of this is to add some extra randomness
    function rngRequest( uint256 _nonce, string memory _functionName, uint8 _rngCount, address _callerContract, uint256 _numConfirmations, uint256 _clientSeed, address _clientWalletAddress) external {
        if (msg.sender != supraRouterContract) revert RouterOnly();
        emit RequestGenerated(_nonce, instanceId, _callerContract, _functionName, _rngCount, _numConfirmations, _clientSeed, _clientWalletAddress);
    }

    /// @notice It will call back the router contract with random number requested for the particular client address
    /// @dev It will generate the call back to router contract for the particular request with it's respective parameters
    /// @param _nonce nonce is an incremental counter which is associated with request
    /// @param _bhash Hash value
    /// @param _message Message data
    /// @param _signature Signature which is generated from supra client
    /// @param _rngCount Number of random numbers requested
    /// @param clientSeed Use of this is to add some extra randomness
    /// @param _callerContract Actual client contract address from which request has been generated
    /// @param _func A combination of a function and the types of parameters it takes, combined together as a string with no spaces
    /// @return success It will return status of request
    /// @return data data we get by calling router contract
    function generateRngCallback(uint256 _nonce, bytes32 _bhash, bytes memory _message, uint256[2] calldata _signature, uint8 _rngCount,uint256 clientSeed, address _callerContract, string calldata _func, address _clientWalletAddress, uint256 _txnFee) public nonReentrant() returns(bool, bytes memory){
        if (!isFreeNodeWhitelisted[msg.sender]) revert FreeNodeNotWhitelisted();
        if (nonceUsed[_nonce]) revert NonceUsed();
        if (_txnFee >= _depositContract.checkClientFund(_clientWalletAddress)) revert InsufficientFunds();
        // Verify that the passed parameters do indeed hash to _message to ensure that the params
        // are not spoofed
        bytes memory encoded_data = abi.encode(_bhash, _nonce, _rngCount, instanceId, _callerContract, _func, clientSeed);
        bytes32 keccak_encoded = keccak256(encoded_data);
        if (keccak_encoded != bytes32(_message)) revert ParamsSignedMessageMismatch();
        // Verify the signature using the public key
        if (!verify(_message, _signature)) revert SigVerifyFailed();
        // Generate a random number
        // Use the signature as a seed and some transaction parameters, generate hash and convert to uint for random number
        uint256[] memory rngList = new uint256[](_rngCount);
        for(uint256 loop; loop<_rngCount; ++loop) {
            rngList[loop] = uint256(keccak256(abi.encodePacked(_signature,loop+1)));
        }
        (bool success, bytes memory data) = supraRouterContract.call(abi.encodeWithSignature('rngCallback(uint256,uint256[],address,string)', _nonce, rngList, _callerContract, _func ));
        _depositContract.collectFund(_clientWalletAddress, _txnFee);
        nonceUsed[_nonce] = true;
        emit NonceProcessed(_nonce,_clientWalletAddress,block.timestamp);
        return(success,data);
    }

    /// @notice The function will whitelist a single free node wallet
    /// @dev The function will whitelist a single free node at a time and will only be updated by the owner
    /// @param _freeNodeWallet this is the wallet address to be whitelisted
    function addFreeNodeToWhitelistSingle(address _freeNodeWallet) external onlyOwner {
        if (isFreeNodeWhitelisted[_freeNodeWallet]) revert FreeNodeAlreadyWhitelisted();
        isFreeNodeWhitelisted[_freeNodeWallet] = true;
    }

    /// @notice The function will whitelist multiple free node wallets
    /// @dev The function will whitelist multiple free node addresses passed altogether in an array
    /// @param _freeNodeWallets it is an array of address type, which accepts all the addresses to whitelist altogether
    function addFreeNodeToWhitelistBulk(address[] memory _freeNodeWallets) external onlyOwner {
        for (uint256 loop=0; loop<_freeNodeWallets.length; loop++) {
            if (isFreeNodeWhitelisted[_freeNodeWallets[loop]]) revert FreeNodeAlreadyWhitelisted();
            isFreeNodeWhitelisted[_freeNodeWallets[loop]] = true;
        }
    }

    /// @notice The function will remove the address from the whitelist
    /// @dev The function will remove the already whitelisted free node wallet
    /// @param _freeNodeWallet this is the wallet address that is to be removed from the list of whitelisted free node
    function removeFreeNodeFromWhitelist(address _freeNodeWallet) external onlyOwner {
        if (!isFreeNodeWhitelisted[_freeNodeWallet]) revert FreeNodeNotWhitelisted();
        isFreeNodeWhitelisted[_freeNodeWallet] = false;
    }


    /// @notice This function will be used to update public key
    /// @dev Update the public key state variable
    /// @param _publicKey New Public key which will update the old one
    /// @return bool It returns the status of updation of public key
    function updatePublicKey(uint256[4] memory _publicKey) external onlyOwner returns(bool) {
        publicKey = _publicKey;
        emit PublicKeyUpdated(block.timestamp);
        return true;
    }

    ///@notice This function is for updating the Deposit Contract Address
    ///@dev To update deposit contract address
    ///@param _contractAddress contract address of the deposit/new deposit contract
    function updateDepositContract(address _contractAddress) external onlyOwner {
        if (!isContract(_contractAddress)) revert AddressIsNotContract();
        if (_contractAddress == address(0)) revert InvalidAddress();
        depositContract = _contractAddress;
        _depositContract = IDepositContract(_contractAddress);
    }

    function verify(bytes memory _message, uint256[2] calldata _signature) internal view returns (bool) {
        bool callSuccess;
        bool checkSuccess;
        (checkSuccess, callSuccess) = BLS.verifySingle(_signature, publicKey, BLS.hashToPoint(domain, _message));

        if (!callSuccess) revert PrecompileCallFailed();
        if (!checkSuccess) revert InvalidSig();

        return true;
    }

    function isContract(address _addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

}

