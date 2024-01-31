// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/*           
                                                                                                                                                                                                                                                                                   
  ,----..                                                 ____                        ___     
 /   /   \                                              ,'  , `. ,--,               ,--.'|_   
|   :     : __  ,-.  ,---.                           ,-+-,.' _ ,--.'|        ,---,  |  | :,'  
.   |  ;. ,' ,'/ /| '   ,'\  .--.--.   .--.--.    ,-+-. ;   , ||  |,     ,-+-. /  | :  : ' :  
.   ; /--`'  | |' |/   /   |/  /    ' /  /    '  ,--.'|'   |  |`--'_    ,--.'|'   .;__,'  /   
;   | ;   |  |   ,.   ; ,. |  :  /`./|  :  /`./ |   |  ,', |  |,' ,'|  |   |  ,"' |  |   |    
|   : |   '  :  / '   | |: |  :  ;_  |  :  ;_   |   | /  | |--''  | |  |   | /  | :__,'| :    
.   | '___|  | '  '   | .; :\  \    `.\  \    `.|   : |  | ,   |  | :  |   | |  | | '  : |__  
'   ; : .';  : |  |   :    | `----.   \`----.   |   : |  |/    '  : |__|   | |  |/  |  | '.'| 
'   | '/  |  , ;   \   \  / /  /`--'  /  /`--'  |   | |`-'     |  | '.'|   | |--'   ;  :    ; 
|   :    / ---'     `----' '--'.     '--'.     /|   ;/         ;  :    |   |/       |  ,   /  
 \   \ .'                    `--'---'  `--'---' '---'          |  ,   /'---'         ---`-'   
  `---`                                                         ---`-'                        
                                                                                              
*/

import "./ERC1155URIStorageUpgradeable.sol";
import "./DefaultOperatorFiltererUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./IERC1155.sol";
import "./ERC2981.sol";
import "./CrossmintMintAPI.sol";

/**
 * @dev Crossmint's default 1155 contract for the mint API, it's main features include
 * royalty handling, operator filtering, and updating metadata.
 */
contract Upgradeable1155 is
    Initializable,
    AccessControlUpgradeable,
    DefaultOperatorFiltererUpgradeable,
    ERC1155URIStorageUpgradeable,
    ERC2981,
    CrossmintMintAPI
{
    string public name;
    string public symbol;
    address public primaryRoyaltyRecipient;
    uint256 public royaltyBps;
    bool public openseaFilterEnabled;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // This will only ever run while deploying the implementation contract
        // and it's here to make sure that it's never initialized
        _disableInitializers();
    }

    // Modifiers

    /**
     * @dev Modifier to check if the sender is an allowed operator for a specific address,
     *      only when OpenSea filter is enabled.
     * @param from The address from which the operation is performed.
     */
    modifier onlyAllowedOperatorIfEnabled(address from) {
        if (openseaFilterEnabled && from != msg.sender) {
            _checkFilterOperator(msg.sender);
        }
        _;
    }

    /**
     * @dev Modifier to check if the sender is an allowed operator for approval,
     *      only when OpenSea filter is enabled.
     * @param operator The address of the operator being approved.
     */
    modifier onlyAllowedOperatorApprovalIfEnabled(address operator) {
        if (openseaFilterEnabled) {
            _checkFilterOperator(msg.sender);
        }
        _;
    }

    /**
     * @dev Initializes the contract.
     * @param owner The address to set as the owner of the contract.
     * @param _name The name of the contract.
     * @param _symbol The symbol of the contract.
     */
    function initialize(
        address owner,
        string memory _name,
        string memory _symbol
    ) public initializer {
        __ERC1155_init("");
        __ERC1155URIStorage_init();
        __AccessControl_init();
        __DefaultOperatorFilterer_init();

        name = _name;
        symbol = _symbol;

        openseaFilterEnabled = true;
        royaltyBps = 0;

        require(owner != address(0), "owner is the zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, owner);
    }

    // Admin

    /**
     * @dev Sets the royalty information for the contract.
     * @param recipient The address of the royalty recipient.
     * @param bps The basis points (0-10000) of the royalty amount.
     */
    function setRoyaltyInfo(
        address recipient,
        uint256 bps
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        royaltyBps = bps;
        primaryRoyaltyRecipient = recipient;
    }

    /**
     * @dev Sets whether the OpenSea filter is enabled.
     * @param enabled Boolean indicating if the filter is enabled.
     */
    function setOpenseaFilterEnabled(
        bool enabled
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        openseaFilterEnabled = enabled;
    }

    /**
     * @dev Sets the token URI for a specific token.
     * @param tokenId The id of the token.
     * @param _tokenURI The URI of the token metadata.
     */
    function setTokenURI(
        uint256 tokenId,
        string memory _tokenURI
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(tokenId, _tokenURI);
    }

    /**
     * @dev Burns a specific amount of tokens.
     * @param from The address from which the tokens will be burned.
     * @param id The id of the token.
     * @param amount The amount of tokens to burn.
     */
    function burn(
        address from,
        uint256 id,
        uint256 amount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _burn(from, id, amount);
    }

    /**
     * @dev Mints a new token and assigns it to a recipient.
     * @param recipient The address to receive the minted tokens.
     * @param amount The amount of tokens to mint.
     * @param tokenId The id of the token.
     * @param tokenURI The URI of the token metadata.
     */
    function mintNewToken(
        address recipient,
        uint256 amount,
        uint256 tokenId,
        string memory tokenURI
    ) public payable onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(tokenId, tokenURI);
        mintExistingToken(recipient, amount, tokenId);
    }

    /**
     * @dev Mints existing tokens and assigns them to a recipient.
     * @param recipient The address to receive the minted tokens.
     * @param amount The amount of tokens to mint.
     * @param tokenId The id of the token.
     */
    function mintExistingToken(
        address recipient,
        uint256 amount,
        uint256 tokenId
    ) public payable onlyRole(DEFAULT_ADMIN_ROLE) {
        _mint(recipient, tokenId, amount, "");
    }

    // View

    /**
     * @dev Get the version of the contract.
     * @return version The version of this contract, important since it's upgradable.
     */
    function getVersion()
        public
        view
        virtual
        override
        returns (string memory version)
    {
        return "0.5";
    }

    /**
     * @dev Get the treasury address.
     * @return treasury The address of the treasury.
     */
    function getTreasury()
        public
        view
        virtual
        override
        returns (address treasury)
    {
        return 0xa8C10eC49dF815e73A881ABbE0Aa7b210f39E2Df;
    }

    /**
     * @dev Temporary function for backwards compatibility reasons
     * @return owner up in the air what exactly this means right now, expect an upgrade soon.
     */
    function owner() public view virtual override returns (address) {
        return 0xa8C10eC49dF815e73A881ABbE0Aa7b210f39E2Df;
    }

    /**
     * @dev Checks if a given interface is supported by this contract.
     * @param interfaceId The interface identifier.
     * @return Boolean indicating if the interface is supported.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC2981, ERC1155Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IERC1155).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev Get the royalty information for a specific token and sale price.
     * @param _tokenId The id of the token.
     * @param _salePrice The sale price of the token.
     * @return receiver The recipient of the royalties.
     * @return royaltyAmount The amount of the royalties.
     */
    function royaltyInfo(
        uint256 _tokenId,
        uint256 _salePrice
    ) public view override returns (address receiver, uint256 royaltyAmount) {
        return (primaryRoyaltyRecipient, (_salePrice * royaltyBps) / 10000);
    }

    // Overrides

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override onlyAllowedOperatorApprovalIfEnabled(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        uint256 amount,
        bytes memory data
    ) public override onlyAllowedOperatorIfEnabled(from) {
        super.safeTransferFrom(from, to, tokenId, amount, data);
    }

    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory tokenIds,
        uint256[] memory amounts,
        bytes memory data
    ) public override onlyAllowedOperatorIfEnabled(from) {
        super.safeBatchTransferFrom(from, to, tokenIds, amounts, data);
    }
}

