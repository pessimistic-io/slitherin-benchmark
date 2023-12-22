// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ILayerrToken
 * @author 0xth0mas (Layerr)
 * @notice ILayerrToken interface defines functions required to be supported by the Layerr platform
 */
interface ILayerrToken {

    /// @dev Emitted when the contract is deployed so that it can be indexed and assigned to its owner
    event LayerrContractDeployed();

    /// @dev Emitted when a mint extension is updated to allowed or disallowed
    event MintExtensionUpdated(address mintExtension, bool allowed);

    /// @dev Emitted when the contract's renderer is updated
    event RendererUpdated(address renderer);

    /// @dev Thrown when a caller that is not a mint extension attempts to execute a mint function
    error NotValidMintingExtension();

    /// @dev Thrown when a non-owner attempts to execute an only owner function
    error NotAuthorized();

    /// @dev Thrown when attempting to withdraw funds from the contract and the call fails
    error WithdrawFailed();

    /**
     * @return name the name of the token
     */
    function name() external view returns(string memory);

    /**
     * @return symbol the token symbol
     */
    function symbol() external view returns(string memory);

    /**
     * @return renderer the address that will render token/contract URIs
     */
    function renderer() external view returns(address);
    
    /**
     * @notice Sets the renderer for token/contract URIs
     * @dev This function should be restricted to contract owners
     * @param _renderer address to set as the token/contract URI renderer
     */
    function setRenderer(address _renderer) external;

    /**
     * @notice Sets whether or not an address is allowed to call minting functions
     * @dev This function should be restricted to contract owners
     * @param _extension address of the mint extension to update
     * @param _allowed if the mint extension is allowed to mint tokens
     */
    function setMintExtension(
        address _extension,
        bool _allowed
    ) external;

    /**
     * @notice This function calls the mint extension to update `_signer`'s allowance
     * @dev This function should be restricted to contract owners
     * @param _extension address of the mint extension to update
     * @param _signer address of the signer to update
     * @param _allowed if `_signer` is allowed to sign for `_extension`
     */
    function setContractAllowedSigner(
        address _extension,
        address _signer,
        bool _allowed
    ) external;

    /**
     * @notice This function calls the mint extension to update `_oracle`'s allowance
     * @dev This function should be restricted to contract owners
     * @param _extension address of the mint extension to update
     * @param _oracle address of the oracle to update
     * @param _allowed if `_oracle` is allowed to sign for `_extension`
     */
    function setContractAllowedOracle(
        address _extension,
        address _oracle,
        bool _allowed
    ) external;

    /**
     * @notice This function calls the mint extension to update signature validity
     * @dev This function should be restricted to contract owners
     * @param _extension address of the mint extension to update
     * @param signatureDigests hash digests of signatures parameters to update
     * @param invalid true if the signature digests should be marked as invalid
     */
    function setSignatureValidity(
        address _extension,
        bytes32[] calldata signatureDigests,
        bool invalid
    ) external;

    /**
     * @notice This function updates the ERC2981 royalty percentages
     * @dev This function should be restricted to contract owners
     * @param pct royalty percentage in BPS
     * @param royaltyReciever address to receive royalties
     */
    function setRoyalty(
        uint96 pct,
        address royaltyReciever
    ) external;

    /**
     * @notice This function updates the token contract's name and symbol
     * @dev This function should be restricted to contract owners
     * @param _name new name for the token contract
     * @param _symbol new symbol for the token contract
     */
    function editContract(
        string calldata _name,
        string calldata _symbol
    ) external;
}
