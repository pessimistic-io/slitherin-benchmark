// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import {Initializable} from "./Initializable.sol";
import {ERC2981Upgradeable} from "./ERC2981Upgradeable.sol";
// import {KreskoCollectionClaimer} from "./KreskoCollectionClaimer.sol";
import {GenericCollectionStore, Roles} from "./GenericCollectionStore.sol";
import {ONFT1155Upgradeable, AccessControlUpgradeable} from "./ONFT1155Upgradable.sol";
import {ILayerZeroEndpointUpgradeable} from "./ILayerZeroEndpointUpgradeable.sol";

/**
 * @title   Kresko NFT Collection
 * @author  Kresko
 * @notice  main contract for the Kresko NFT Collection
 * @dev     This contract is the main contract for the Kresko NFT Collection
  based on the ERC1155, ERC2981 standard. It will be behind a proxy contract
  which allows us to upgrade the contract in the future for integations with
  kresko protocol.
 */
contract KreskoCollection is
    Initializable,
    GenericCollectionStore,
    ONFT1155Upgradeable,
    ERC2981Upgradeable
{
    // Contract name
    string public name;
    // Contract symbol
    string public symbol;
    // Metadata URI for the collection
    string public contractURI;
    // owner
    // @dev even though we have AccessControlEnumerableUpgradeable we still need
    // owner as opensea requires it edit metadata on collection page
    // https://github.com/ProjectOpenSea/opensea-creatures/issues/92
    address public owner;

    /* -------------------------------------------------------------------------- */
    /*                                   Events                                   */
    /* -------------------------------------------------------------------------- */

    event ClaimerDeployed(address claimer);

    /**
     * @notice Collection initialization
     * @param _owner owner, mostly for OpenSea/other external integrations
     * @param _name collection name
     * @param _symbol collection symbol
     * @param _tokenUri metadata uri for tokens
     * @param _contractURI contract level metadata uri
     */
    function initialize(
        address _owner,
        string memory _name,
        string memory _symbol,
        string memory _tokenUri,
        string memory _contractURI
    ) public initializer {
        __ONFT1155Upgradeable_init(_tokenUri, address(0));
        __ERC1155Supply_init();
        __ERC2981_init();

        name = _name;
        symbol = _symbol;
        contractURI = _contractURI;
        owner = _owner;

        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        // CREATE2 factory is the msg.sender
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function afterInitialization(
        address _lzEndpoint,
        address _multisig,
        address _treasury,
        uint96 _feeNumerator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lzEndpoint = ILayerZeroEndpointUpgradeable(_lzEndpoint);
        _grantRole(DEFAULT_ADMIN_ROLE, _multisig);
        _setDefaultRoyalty(_treasury, _feeNumerator);
    }

    function setupLZ(
        address _lzEndpoint
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lzEndpoint = ILayerZeroEndpointUpgradeable(_lzEndpoint);
    }

    /* -------------------------------------------------------------------------- */
    /*                            Authorized functions                            */
    /* -------------------------------------------------------------------------- */

    /* --------------------------------- Supply --------------------------------- */

    /**
     * @notice Allows Roles.MINTER_ROLE to mint tokens to a given address
     * @param _to address to mint the NFT to
     * @param _tokenId token id to mint
     * @param _amount amount to mint
     */
    function mint(
        address _to,
        uint256 _tokenId,
        uint256 _amount
    ) external onlyRole(Roles.MINTER_ROLE) {
        _mint(_to, _tokenId, _amount, "");
    }

    /**
     * @notice Allows Roles.MINTER_ROLE to burn tokens from a given address
     * @param _from address to burn the NFT from
     * @param _id token id to burn
     * @param _amount amount to burn
     */
    function burn(
        address _from,
        uint256 _id,
        uint256 _amount
    ) external onlyRole(Roles.MINTER_ROLE) {
        _burn(_from, _id, _amount);
    }

    /* ------------------------------ Configuration ----------------------------- */

    /// @dev Allows admin to set tokenURI
    /// @param _newURI new uri to set
    function setURI(
        string calldata _newURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(_newURI);
    }

    /// @dev Allows admin to set the contract URI
    /// @param _contractURI new contract URI to set
    function setContractURI(
        string calldata _contractURI
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        contractURI = _contractURI;
    }

    /**
     * @notice Changes the contract owner
     * @param _owner new owner
     */
    function changeOwner(address _owner) external {
        require(msg.sender == owner, "!owner");
        owner = _owner;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Royalty                                  */
    /* -------------------------------------------------------------------------- */

    /**
     * @notice Configures the royalties
     *
     * @param _tokenId token id to set the royalty for
     * @param _receiver address of the royalty receiver
     * @param _feeNumerator feeNumerator of the royalty
     * @param _action 0 = reset, 1 = set default, 2 = set tokenId
     */
    function configureRoyalty(
        uint256 _tokenId,
        address _receiver,
        uint96 _feeNumerator,
        uint8 _action
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_action == 0) {
            _resetTokenRoyalty(_tokenId);
        } else if (_action == 1) {
            _setDefaultRoyalty(_receiver, _feeNumerator);
        } else if (_action == 2) {
            _setTokenRoyalty(_tokenId, _receiver, _feeNumerator);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                               View functions                               */
    /* -------------------------------------------------------------------------- */

    /// @dev Returns true if the contract implements the interface defined by
    /// @param _interfaceId interface identifier
    function supportsInterface(
        bytes4 _interfaceId
    )
        public
        view
        override(
            ONFT1155Upgradeable,
            ERC2981Upgradeable,
            AccessControlUpgradeable
        )
        returns (bool)
    {
        return super.supportsInterface(_interfaceId);
    }
}

