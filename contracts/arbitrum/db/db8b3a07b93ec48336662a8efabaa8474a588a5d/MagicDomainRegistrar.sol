// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {     ERC721Upgradeable,     IERC721Upgradeable,     Initializable,     IERC165Upgradeable } from "./ERC721Upgradeable.sol";
import {ControllableAbs} from "./ControllableAbs.sol";

import {IMagicDomainRegistrar} from "./IMagicDomainRegistrar.sol";
import {IMagicDomainRegistry} from "./IMagicDomainRegistry.sol";

contract MagicDomainRegistrar is IMagicDomainRegistrar, ERC721Upgradeable, ControllableAbs {

    // The Magic registry
    IMagicDomainRegistry public magicDomainRegistry;
    // The namehash of the TLD this registrar owns (eg, .magic)
    bytes32 public baseNode;

    mapping(address => uint256) public userToOwnedSubdomainToken;
    mapping(uint256 => SubdomainMetadata) public tokenMetadata;

    bytes4 private constant ERC165_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 private constant RECLAIM_ID = bytes4(keccak256("reclaim(uint256,address)"));

    // The URI prefix used to assemble a tokenURI.
    string public baseURI;

    uint256 public totalMinted;
    uint256 public totalBurned;

    /**
     * @dev Initializes the contract by setting registry reference and base node (.magic).
     */
    function initialize(IMagicDomainRegistry _magicDomainRegistry, bytes32 _baseNode) external initializer {
        __Controllable_init();
        __ERC721_init("", "");
        magicDomainRegistry = _magicDomainRegistry;
        baseNode = _baseNode;
    }

    // ---------
    // External
    // ---------

    /**
     * @dev Reclaim ownership of a name in MagicDomainRegistry, if you own it in the registrar.
     */
    function reclaim(string memory _name, string memory discriminant, address owner) external override live {
        uint256 id = tagToId(_name, discriminant);
        require(_isApprovedOrOwner(msg.sender, id), "MagicDomainRegistrar: not owner or approved");
        magicDomainRegistry.setSubnodeOwner(_getDiscriminantSubnode(discriminant), nameToLabel(_name), owner);
    }

    // ---------
    // Views
    // ---------

    // Returns true if the specified name is available for registration.
    function available(uint256 id) public view override returns (bool) {
        // Not available if it's got an owner.
        return !_exists(id);
    }

    function tagToId(string memory _name, string memory discriminant) public pure returns(uint256 tokenId_) {
        tokenId_ = uint256(keccak256(bytes(string.concat(_name, "#", discriminant))));
    }

    /**
     * @dev Check for supporting supportsInterface, ERC721 standard, and specifically reclaiming.
     *  We do not reference type(IMagicDomainRegistrar).interfaceId because any contract referencing this func
     *  could be outdated if this contract gets redeployed with a modified interface
     */
    function supportsInterface(bytes4 _interfaceId) public pure override returns (bool) {
        return _interfaceId == ERC165_ID 
            || _interfaceId == RECLAIM_ID
            || _interfaceId == type(IERC721Upgradeable).interfaceId;
    }

    // ---------
    // Admin
    // ---------

    /**
     * @dev Register a node by semi unique name & discriminant.
     * @param _name The semi unique name to register.
     * @param discriminant The discriminant to make the name unique.
     * @param owner The address that should own the registration.
     */
    function register(
        string memory _name,
        string memory discriminant,
        address owner
    ) external override live onlyController {
        require(balanceOf(owner) == 0, "MagicDomainRegistrar: Already owns a magic domain");
        uint256 id = tagToId(_name, discriminant);
        require(available(id), "MagicDomainRegistrar: Token unavailable");

        _register(_name, discriminant, owner, id);
    }

    /**
     * @dev Exchanges the owner's current name for a new one.
     * @param newName The new semi unique name.
     * @param discriminant The discriminant to make the name unique.
     * @param owner The address that should own the new name.
     */
    function changeName(
        string memory newName,
        string memory discriminant,
        address owner
    ) external override live onlyController {
        uint256 newId = tagToId(newName, discriminant);
        require(available(newId), "MagicDomainRegistrar: Token unavailable");
        uint256 oldNameId = userToOwnedSubdomainToken[owner];
        require(_ownerOf(oldNameId) == owner, "MagicDomainRegistrar: Not owner or doesn't exist");

        // Remove old token + registry record
        _burn(oldNameId);
        magicDomainRegistry.removeSubnodeRecord(
            _getDiscriminantSubnode(tokenMetadata[oldNameId].discriminant),
            nameToLabel(tokenMetadata[oldNameId].name)
        );
        emit NameRemoved(oldNameId, owner);

        _register(newName, discriminant, owner, newId);
    }

    // Set the resolver for the TLD this registrar manages.
    function setResolver(address resolver) external override onlyOwner {
        magicDomainRegistry.setResolver(baseNode, resolver);
    }

    /**
     * @dev Sets the baseURI for the contract.
     * @param newBaseURI The new baseURI (must include a trailing '/').
     */
    function setBaseURI(string memory newBaseURI) external onlyOwner {
        emit BaseURIChanged(baseURI, newBaseURI);
        baseURI = newBaseURI;
    }

    /**
     * @dev Sets the initial mint/burn numbers for token tracking. Only used due to deploying without proper tracking in place.
     * @param _numMinted The number of tokens minted before tracking
     * @param _numBurned The number of tokens burned before tracking
     */
    function seedSupplyNumber(uint256 _numMinted, uint256 _numBurned) external onlyOwner {
        require(totalMinted == 0 && totalBurned == 0, "MagicDomainRegistrar: mints / burns have occurred");
        require(_numMinted >= _numBurned, "MagicDomainRegistrar: Burned exceeds minted");
        totalMinted = _numMinted;
        totalBurned = _numBurned;
    }

    // ---------
    // Internal
    // ---------

    function _register(string memory _name, string memory discriminant, address owner, uint256 id) internal {
        tokenMetadata[id] = SubdomainMetadata({
            name: _name,
            discriminant: discriminant
        });
        _mint(owner, id);
        
        bytes32 discriminantSubnode = _getDiscriminantSubnode(discriminant);
        // If the discriminant subnode hasn't been initialized, do so
        // Assumes that this registrar is the owner/operator of the .magic TLD
        if(magicDomainRegistry.owner(discriminantSubnode) == address(0)) {
            magicDomainRegistry.setSubnodeOwner(baseNode, nameToLabel(discriminant), address(this));
        }

        // Creates a subnode ref for the discriminant and attaches the semi unique name to it.
        // This ensures that the name#discriminant combo is unique, and resolving goes through name.discriminant.magic
        // The token is the unique combination of name+discriminant
        // Ex: myname#1234
        // tokenId = uint256(keccack256("myname#1234"))
        // subnode path: 0x0 -> magic -> 1234 -> myname
        magicDomainRegistry.setSubnodeOwner(
            discriminantSubnode,
            nameToLabel(_name),
            owner
        );

        magicDomainRegistry.setBlockSubnodeForSubnode(
            discriminantSubnode,
            nameToLabel(_name),
            true
        );

        emit NameRegistered(id, owner);
    }

    function _getDiscriminantSubnode(string memory discriminant) internal view returns(bytes32 subnode_) {
        subnode_ = keccak256(abi.encodePacked(baseNode, nameToLabel(discriminant)));
    }

    function nameToLabel(string memory _name) internal pure returns(bytes32 label_) {
        label_ = bytes32(keccak256(bytes(_name)));
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    // ---------
    // Modifiers
    // ---------

    modifier live() {
        require(magicDomainRegistry.owner(baseNode) == address(this), "MagicDomainRegistrar: not live");
        _;
    }

    // ---------
    // Overrides
    // ---------

    /**
     * @dev Overrides the default tokenURI. See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireMinted(tokenId);

        string memory prefix = _baseURI();
        return bytes(prefix).length > 0 ? string(abi.encodePacked(prefix, tokenMetadata[tokenId].name, "/", tokenMetadata[tokenId].discriminant)) : "";
    }

    /**
     * @notice Displays the total number of tokens in existence. Per EIP-721, removes burned tokens from number.
     */
    function totalSupply() external view returns(uint256 supply_) {
        supply_ = totalMinted - totalBurned;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return unicode"✨TreasureTags";
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return unicode"✨";
    }
    
    /**
     * @dev See {ERC721-_beforeTokenTransfer}.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        require(batchSize == 1, "MagicDomainRegistrar: Invalid transfer size");
        require(from == address(0) || to == address(0), "MagicDomainRegistrar: Tokens are soulbound");

        if (from == address(0)) {
            userToOwnedSubdomainToken[to] = tokenId;
            totalMinted++;
        } else if (to == address(0)) {
            userToOwnedSubdomainToken[from] = 0;
            totalBurned++;
        } else {
            revert("MagicDomainRegistrar: Invalid transfer action");
        }
    }

}

