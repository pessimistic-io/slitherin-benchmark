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

import "./IERC721.sol";
import "./ERC721URIStorageUpgradeable.sol";
import "./ERC2981.sol";

import "./AccessControlUpgradeable.sol";
import "./Initializable.sol";
import "./CountersUpgradeable.sol";

import "./DefaultOperatorFiltererUpgradeable.sol";
import "./CrossmintMintAPI.sol";

/**
 * @dev Crossmint's default 721 contract for the mint API, it's main features include
 * royalty handling, operator filtering, updating metadata, and toggling transferability.
 */
contract Upgradeable721 is
    Initializable,
    AccessControlUpgradeable,
    ERC721URIStorageUpgradeable,
    DefaultOperatorFiltererUpgradeable,
    ERC2981,
    CrossmintMintAPI
{
    bool public transferable;
    address public primaryRoyaltyRecipient;
    bool public openseaFilterEnabled;
    uint256 public royaltyBps;

    string private _name;
    string private _symbol;

    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private currentId;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // This will only ever run while deploying the implementation contract
        // and it's here to make sure that it's never initialized
        _disableInitializers();
    }

    // Modifiers

    /**
     * @dev Ensures the function is only called by allowed operator if the OpenSea filter is enabled.
     * @param from The address from which the function is called.
     */
    modifier onlyAllowedOperatorIfEnabled(address from) {
        if (openseaFilterEnabled && from != msg.sender) {
            _checkFilterOperator(msg.sender);
        }
        _;
    }

    /**
     * @dev Ensures the function is only called by allowed operator if the OpenSea filter is enabled.
     * @param operator The operator for which approval is being given.
     */
    modifier onlyAllowedOperatorApprovalIfEnabled(address operator) {
        if (openseaFilterEnabled) {
            _checkFilterOperator(msg.sender);
        }
        _;
    }

    /**
     * @dev Initialize the contract. Can only be called once.
     * @param admin The initial admin of the contract.
     * @param _transferable The transferability status of the token.
     * @param __name The name of the token.
     * @param __symbol The symbol of the token.
     */
    function initialize(
        address admin,
        bool _transferable,
        string memory __name,
        string memory __symbol
    ) public initializer {
        __ERC721_init("", "");
        __ERC721URIStorage_init();
        __AccessControl_init();
        __DefaultOperatorFilterer_init();

        _name = __name;
        _symbol = __symbol;
        openseaFilterEnabled = true;
        royaltyBps = 0;
        transferable = _transferable;

        require(admin != address(0), "admin is the zero address");
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // Admin

    /**
     * @dev Set the name of the token.
     * @param __name The new name of the token.
     */
    function setName(string memory __name) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _name = __name;
    }

    /**
     * @dev Set the symbol of the token.
     * @param __symbol The new symbol of the token.
     */
    function setSymbol(
        string memory __symbol
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _symbol = __symbol;
    }

    /**
     * @dev Enable or disable the OpenSea filter.
     * @param enabled The new status of the OpenSea filter.
     */
    function setOpenseaFilterEnabled(
        bool enabled
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        openseaFilterEnabled = enabled;
    }

    /**
     * @dev Set the royalty information.
     * @param recipient The address to receive the royalties.
     * @param bps The basis points percentage of the royalties.
     */
    function setRoyaltyInfo(
        address recipient,
        uint256 bps
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        royaltyBps = bps;
        primaryRoyaltyRecipient = recipient;
    }

    /**
     * @dev Set the transferability of the token.
     * @param value The new transferability status of the token.
     */
    function setTransferable(bool value) public onlyRole(DEFAULT_ADMIN_ROLE) {
        transferable = value;
    }

    /**
     * @dev Set the token URI of a specific token.
     * @param tokenId The id of the token.
     * @param _tokenURI The new URI of the token.
     */
    function setTokenURI(
        uint256 tokenId,
        string memory _tokenURI
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTokenURI(tokenId, _tokenURI);
    }

    /**
     * @dev Burn a specific token.
     * @param tokenId The id of the token to burn.
     */
    function burn(uint256 tokenId) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _burn(tokenId);
    }

    /**
     * @dev Mint a new token to a specific address and set its URI.
     * @param recipient The address to receive the newly minted token.
     * @param tokenURI The URI of the newly minted token.
     * @return id The id of the newly minted token.
     */
    function mintTo(
        address recipient,
        string memory tokenURI
    ) public payable onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256 id) {
        currentId.increment();

        uint256 newItemId = currentId.current();
        _mint(recipient, newItemId);
        _setTokenURI(newItemId, tokenURI);

        return newItemId;
    }

    // View

    /**
     * @dev Get the symbol of the token.
     * @return The symbol of the token.
     */
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Get the name of the token.
     * @return The name of the token.
     */
    function name() public view override returns (string memory) {
        return _name;
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

    /**
     * @dev Check if the contract supports a specific interface.
     * @param interfaceId The id of the interface.
     * @return A boolean indicating whether the contract supports the interface.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(ERC2981, ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IERC721).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    // Overrides

    /**
     * @dev Get the version of the contract.
     * @return version the version of this contract, important since it's upgradable.
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

    // Block transfers if this contract is configured that way
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721Upgradeable) {
        // Mints are from the 0 address
        require(from == address(0) || transferable, "Token not transferable");
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // The following function are overriden to enforce Opensea's operator filter

    function setApprovalForAll(
        address operator,
        bool approved
    ) public override onlyAllowedOperatorApprovalIfEnabled(operator) {
        super.setApprovalForAll(operator, approved);
    }

    function approve(
        address operator,
        uint256 tokenId
    ) public override onlyAllowedOperatorApprovalIfEnabled(operator) {
        super.approve(operator, tokenId);
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyAllowedOperatorIfEnabled(from) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override onlyAllowedOperatorIfEnabled(from) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public override onlyAllowedOperatorIfEnabled(from) {
        super.safeTransferFrom(from, to, tokenId, _data);
    }
}

