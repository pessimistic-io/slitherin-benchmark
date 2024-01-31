// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./ERC721Upgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./Strings.sol";

/**
 * @title GovernanceNFT: ERC721 NFT with URI storage for metadata used for governance in Discord
 * @dev ERC721 contains logic for NFT storage and metadata.
 */
contract GovernanceNFT is ERC721Upgradeable, AccessControlUpgradeable {
    // roles for access control
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    // base URI for NFTs 
    string private baseURI;

    // Because this contract is used through a proxy, new variables can only be appended below the others to keep the thier storage location!

    /**
     * @dev The real initialization is called when deploying the proxy.
     */
    constructor() {}

    /**
     * @dev The constructor for the Governance NFT sets up NFT name and roles
     * @param issuer The address allowed to mint and burn NFTs
     * @param uri base URI to the metadata (id will be concatinated to this)
     * @param owner Owner of the contract (can modify roles)
     * @param nftName Name of the ERC721 NFT
     * @param nftSymbol Symbol of the ERC721 NFT
     */
    function initialize(
        address issuer,
        string memory uri,
        address owner,
        string memory nftName,
        string memory nftSymbol
    ) 
        external
        reinitializer(1)
        // onlyRole(DEFAULT_ADMIN_ROLE) enable this when upgrading
    {
        // set admin, the role that can initialize, assign and revoke other roles 
        _setupRole(DEFAULT_ADMIN_ROLE, owner);
        // only addresses assigned to this role will be able to mint and burn NFTs
        _setupRole(ISSUER_ROLE, issuer);

        __ERC721_init(nftName, nftSymbol);
        
        baseURI = uri;
    }

    /**
     * @dev Mint a NFT for a user
     * @param user Address that should receive the NFT
     */
    function mint(address user)
        public
        onlyRole(ISSUER_ROLE)
    {
        // the id of each NFT will be uniquely defined by the user holding it
        // 1 to 1 relation
        uint256 newNFTId = getIDForAddress(user);
        // using _mint instead of _safeMint to prevent the contract from reverting
        //  if a smart contract is staking and has not implemented the onERC721Received function
        _mint(user, newNFTId);
    }

    /**
     * @dev Mint a NFT for a batch of user
     * @param users Array of address that should receive the NFT
     */
    function batchMint(address[] calldata users)
        public
        onlyRole(ISSUER_ROLE)
    {
        for (uint i = 0; i < users.length; i++) {
            uint256 newNFTId = getIDForAddress(users[i]);
            // if (_exists(newNFTId)) {
            //     // prevent large batch tx from failing if one NFT was already minted:
            //     continue;
            // }
            _mint(users[i], newNFTId);
        }
    }

    /**
     * @dev Burn a NFT of a user
     * @param user Address that should have the NFT burned. Information about the holder is enough because there is as most one NFT per user.
     */
    function burn(address user)
        public
        onlyRole(ISSUER_ROLE)
    {
        // the id of each NFT will be uniquely defined by the user holding it
        // 1 to 1 relation
        uint256 id = getIDForAddress(user);
        _burn(id);
    }

    /**
     * @dev Get NFT id of user or 0 for none.
     * 
     * @param user The address of the NFT owner.
     * @return Returns the id of the NFT for the given address and 0 if the address has no NFTs.
     */
    function getNFTHoldBy(address user)
        public view
        returns (uint256)
    {
        uint256 id = getIDForAddress(user);
        if (balanceOf(user) == 1) {
            assert (ownerOf(id) == user);
            return id;
        }
        return 0;
    }

    /**
     * Implementing ERC165 as needed by AccessControl and ERC721
     */
    function supportsInterface(bytes4 interfaceId) public view override(ERC721Upgradeable, AccessControlUpgradeable) returns (bool) {
        return ERC721Upgradeable.supportsInterface(interfaceId) || AccessControlUpgradeable.supportsInterface(interfaceId);
    }

    /**
     * @dev Each address can at most have one NFT. This function assigns as id to a user by convertng the address to uint256
     * @param user address of the user
     */
    function getIDForAddress(address user)
        public pure
        returns (uint256)
    {
        return uint256(uint160(user));
    }

    /**
     * @dev Each address can at most have one NFT. This function get the address belonging to an id
     * @param id NFT id
     */
    function getAddressForID(uint256 id)
        public pure
        returns (address)
    {
        return address(uint160(id));
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);
        // concatinate base URI with holder address
        // address will be lower case and not have checksum encoding
        return string(abi.encodePacked(_baseURI(), Strings.toHexString(getAddressForID(tokenId)), ".json"));
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`.
     */
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /**
     * @dev Transfers are rejected because the GovernanceNFT is soulbound.
     */
    function _transfer(address, address, uint256) internal pure override {
        revert("GovernanceNFT: transfer is not allowed");
    }


    /**
     * @dev Approve are rejected because the GovernanceNFT is soulbound.
     */
    function _approve(address to, uint256 id) internal override {
        if (to == address(0)){
            // ok to approve zero address as done by the ERC721 implementation on burning
            super._approve(to, id);
        }
        else{
            revert("GovernanceNFT: transfer approval is not allowed");
        }
    }
}
