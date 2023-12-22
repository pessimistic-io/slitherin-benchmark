// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.19;

/// @title ISupraRouterContract interface
/// @dev contains the relevant functions used to request randomness from the Supra VRF Router
interface ISupraRouterContract {
    /// @notice Generates the random number request to generator contract with client's randomness added
    /// @dev It will forward the random number generation request by calling generator contracts function which takes seed value other than required parameter to add randomness
    /// @param _functionSig A combination of a function and the types of parameters it takes, combined together as a string with no spaces
    /// @param _rngCount Number of random numbers requested
    /// @param _numConfirmations Number of Confirmations
    /// @param _clientSeed Use of this is to add some extra randomness
    /// @return nonce nonce is an incremental counter which is associated with request
    function generateRequest(
        string memory _functionSig,
        uint8 _rngCount,
        uint256 _numConfirmations,
        uint256 _clientSeed,
        address _clientWalletAddress
    ) external returns (uint256 nonce);

    /// @notice Generates the random number request to generator contract
    /// @dev It will forward the random number generation request by calling generator contracts function
    /// @param _functionSig A combination of a function and the types of parameters it takes, combined together as a string with no spaces
    /// @param _rngCount Number of random numbers requested
    /// @param _numConfirmations Number of Confirmations
    /// @return nonce nonce is an incremental counter which is associated with request
    function generateRequest(
        string memory _functionSig,
        uint8 _rngCount,
        uint256 _numConfirmations,
        address _clientWalletAddress
    ) external returns (uint256 nonce);

    /// @notice This is the callback function to serve random number request
    /// @dev This function will be called from generator contract address to fulfill random number request which goes to client contract
    /// @param nonce nonce is an incremental counter which is associated with request
    /// @param _clientContractAddress Actual contract address from which request has been generated
    /// @param _functionSig A combination of a function and the types of parameters it takes, combined together as a string with no spaces
    /// @return success bool variable which shows the status of request
    /// @return data data getting from client contract address
    function rngCallback(
        uint256 nonce,
        uint256[] memory rngList,
        address _clientContractAddress,
        string memory _functionSig
    ) external returns (bool success, bytes memory data);

    /// @notice Getter for returning the Supra Deposit Contract address
    /// @return depositContract Supra Deposit Contract address
    function _depositContract() external view returns (address depositContract);

    /// @notice Getter for returning Generator contract address used to forward random number requests
    /// @return supraGeneratorContract Supra Generator Contract address
    function _supraGeneratorContract()
        external
        view
        returns (address supraGeneratorContract);
}

