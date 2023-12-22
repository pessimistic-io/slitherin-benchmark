// SPDX-License-Identifier: MIT
// Creator: kubko

pragma solidity ^0.8.4;

import "./ERC721A.sol";
import "./Ownable.sol";

contract ConstructingBeauty is ERC721A, Ownable {

    /* ///////////////////////////////////////////////////////////////
    VARIABLES
    ////////////////////////////////////////////////////////////// */

    // address of a collection folder on Arweave
    // basically a URI prefix that all tokens share
    string public baseURI;

    // address of collection information such as name, description, image, royalty settings, etc.
    string public contractURI;

    // how many tokens are in the collection
    uint256 public immutable maxSupply;

    // information about every redemption
    struct Redemption {
        string redemptionId;
        address redeemer;
    }

    // how many tokens have been redeemed so far and what addresses redeemed them
    mapping(uint256 => Redemption) public redeemed;

    /* ///////////////////////////////////////////////////////////////
    EVENTS
    ////////////////////////////////////////////////////////////// */

    // triggered when a token is airdropped to a wallet from the yiume team
    event AirdroppedToken(address minter, address recipient, uint256 amount);

    // triggered when a base URI of a token is changed
    event BaseURIChanged(string newBaseURI);

    // triggered when a contract URI of the collection is changed
    event ContractURIChanged(string newContractURI);

    // triggered when a piece is redeemed
    event Redeemed(address redeemer, uint256 tokenId, string redemptionId);

    /**
     * @dev
     * `initBaseURI` refers to an address of a collection folder on Arweave
     * `initContractURI` refers to an address of a collection metadata on Arweave
     * `_maxSupply` refers to how many tokens are in the collection.
     */
    constructor(
        string memory initBaseURI,
        string memory initContractURI,
        uint256 _maxSupply
    )
    ERC721A(
        "constructingBeauty",
        "rya"
    )
    {
        baseURI = initBaseURI;
        contractURI = initContractURI;
        maxSupply = _maxSupply;
    }

    /* ///////////////////////////////////////////////////////////////
    EXTERNAL USER FACING FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Redeems a token for real life piece of garment.
     * @param  tokenId : ID of the token to redeem.
     */
    function redeem(uint256 tokenId, string calldata redemptionId) external {
        require(_exists(tokenId), "Token does not exist");
        require(_ownershipOf(tokenId).addr == msg.sender, "Token not owned by the redeemer");
        require(redeemed[tokenId].redeemer == address(0), "Token already redeemed");

        redeemed[tokenId] = Redemption(redemptionId, msg.sender);

        emit Redeemed(msg.sender, tokenId, redemptionId);
    }

    /* ///////////////////////////////////////////////////////////////
    ACCESS CONTROLLED FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Airdrops a token to the user
     *         A total number of tokens that can be airdropped is limited to `maxSupply`
     * @param  recipients : an array of wallet addresses to receive the token.
     */
    function airdrop(address[] memory recipients) external onlyOwner {
        require(
            totalSupply() + recipients.length <= maxSupply,
            "Max supply exceeded"
        );
        uint256 len = recipients.length;
        for (uint256 i = 0; i < len; i++) {
            require(recipients[i] != address(0), "Zero address");
            _safeMint(recipients[i], 1);

            emit AirdroppedToken(msg.sender, recipients[i], 1);
        }
    }

    /**
     * @notice Set a base Arweave folder URI that holds metadata of tokens
     * @param  newBaseURI : new URI of the metadata folder
     */
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
        emit BaseURIChanged(newBaseURI);
    }

    /**
     * @notice Set a contract URI that holds the metadata about the collection
     * @param  newContractURI : new URI of the collection data
     */
    function setContractURI(string calldata newContractURI) external onlyOwner {
        contractURI = newContractURI;
        emit ContractURIChanged(newContractURI);
    }

    /* ///////////////////////////////////////////////////////////////
    INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns a base URI of a token (a link to the metadata folder on Arweave)
     *      For example: "http://folder.com/hash_value/"
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    /* ///////////////////////////////////////////////////////////////
    GETTERS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Returns a metadata URI of a token
     *         For example, if the base URI is "http://folder.com/" and the token id is 0,
     *         "http://folder.com/0.json" is returned.
     *         The JSON file is the token's metadata.
     * @param  tokenId : id of the token to get the metadata URI of
     */
    function tokenURI(uint256 tokenId)
    public
    view
    virtual
    override
    returns (string memory)
    {
        string memory uri = super.tokenURI(tokenId);
        return
        bytes(uri).length > 0
        ? string(abi.encodePacked(uri, ".json"))
        : "";
    }

    function getOwnershipData(uint256 tokenId)
    external
    view
    returns (TokenOwnership memory)
    {
        return _ownershipOf(tokenId);
    }
}

