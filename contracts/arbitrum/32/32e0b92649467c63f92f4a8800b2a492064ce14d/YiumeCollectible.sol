// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./MerkleProof.sol";
import "./ERC721A.sol";


//      __       _                      ___ _           __   _
//    _/_/__ __ (_)__ __ __ _  ___     / _/(_)____ ___ / /_ | |
//   / / / // // // // //  ' \/ -_)_  / _// // __/(_-</ __/ / /
//  / /  \_, //_/ \_,_//_/_/_/\__/(_)/_/ /_//_/  /___/\__/_/_/
//  |_| /___/                                            /_/


/// Implementation of (yiume.first) collectible that uses ERC721A to save gas fees
contract YiumeCollectible is ERC721A, Ownable, ReentrancyGuard {

    /* ///////////////////////////////////////////////////////////////
    VARIABLES
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Options for sales
     *         NotStarted    : The sale has not started - nobody can mint
     *         AllowlistSale : Only the allowlisted wallet can mint the tokens
     *         PublicSale    : Any wallets can mint the tokens
     *         Finished      : Only the yiume team can reserve tokens using `reserve` function.
     *                         No one else can mint the tokens
     */
    enum Status {
        NotStarted,
        AllowlistSale,
        PublicSale,
        Finished
    }

    // current sales status (either one of the four above)
    Status public status;

    // address of a collection folder on Arweave
    // basically a URI prefix that all tokens share
    string public baseURI;

    // address of collection information such as name, description, image, royalty settings, etc.
    string public contractURI;

    // merkel proof tree root of allowlisted keys
    bytes32 public root;

    // maximum number of tokens one minter can mint during allowlist sale
    uint256 public immutable maxAllowlistMint;

    // maximum number of tokens one minter can mint during public sale
    uint256 public immutable maxPublicMint;

    // how many tokens are in the collection
    uint256 public immutable maxSupply;

    // number of tokens reserved for the yiume team
    uint256 public immutable reserveAmount;

    // number of tokens given out to the yiume team so far
    uint256 public tokensReserved;

    // Mint price. It is 0.
    uint256 public constant PRICE = 0.0 ether;

    /* ///////////////////////////////////////////////////////////////
    EVENTS
    ////////////////////////////////////////////////////////////// */

    // triggered when a token is minted
    event Minted(address minter, uint256 amount);

    // triggered when a sales status is changed (PublicSale to AllowlistSale, for example)
    event StatusChanged(Status status);

    // triggered when a merkle tree root of allowlisted keys is changed
    event RootChanged(bytes32 root);

    // triggered when a token is given out to the yiume team
    event ReservedToken(address minter, address recipient, uint256 amount);

    // triggered when a base URI of a token is changed
    event BaseURIChanged(string newBaseURI);

    // triggered when a contract URI of the collection is changed
    event ContractURIChanged(string newContractURI);

    /**
     * @dev
     * `initBaseURI` refers to an address of a collection folder on Arweave
     * `_maxAllowlistMint` refers to how much an allowlisted minter can mint at maximum during allowlist sales
     * `_maxPublicMint` refers to how much a minter can mint at maximum during public sales
     * `_maxSupply` refers to how many tokens are in the collection.
     * `_reserveAmount` refers to how many tokens are reserved for a team
     */
    constructor(
        string memory initBaseURI,
        string memory initContractURI,
        uint256 _maxAllowlistMint,
        uint256 _maxPublicMint,
        uint256 _maxSupply,
        uint256 _reserveAmount
    )
    ERC721A(
        "(yiume.first)",
        "\u03A8"
    )
    {
        baseURI = initBaseURI;
        contractURI = initContractURI;
        maxAllowlistMint = _maxAllowlistMint;
        maxPublicMint = _maxPublicMint;
        maxSupply = _maxSupply;
        reserveAmount = _reserveAmount;
    }

    /* ///////////////////////////////////////////////////////////////
    EXTERNAL USER FACING FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Mints a token during allowlist sales.
     *         Only a wallet whose key is included in the allowlist can run this function.
     * @dev    Mint using ERC721A
     * @param  amount : amount of tokens to mint
     * @param  proof  : hex proof obtained from the wallet address and a merkle tree of allowlisted addresses.
                        One needs a copy of the entire merkle tree to generate the proof,
                        but usually it is all handled by the yiume website's internal logic
     */
    function allowlistMint(uint256 amount, bytes32[] calldata proof)
    external
    payable
    nonReentrant
    {
        require(status == Status.AllowlistSale, "AllowlistSale is not active.");
        require(
            MerkleProof.verify(proof, root, keccak256(abi.encodePacked(msg.sender))),
            "Invalid proof."
        );
        require(
            numberMinted(msg.sender) + amount <= maxAllowlistMint,
            "Max mint amount per wallet exceeded."
        );
        require(
            totalSupply() + amount + reserveAmount - tokensReserved <=
            maxSupply,
            "Max supply exceeded."
        );

        _safeMint(msg.sender, amount);

        emit Minted(msg.sender, amount);
    }

    /**
     * @notice Mints a token during public sales.
     * @dev    Mint using ERC721A
     * @param  amount : amount of tokens to mint
     */
    function mint(uint256 amount) external payable nonReentrant {
        require(status == Status.PublicSale, "Public sale is not active.");
        require(amount <= maxPublicMint, "Max mint amount per tx exceeded.");
        require(
            totalSupply() + amount + reserveAmount - tokensReserved <=
            maxSupply,
            "Max supply exceeded."
        );

        _safeMint(msg.sender, amount);

        emit Minted(msg.sender, amount);
    }

    /* ///////////////////////////////////////////////////////////////
    ACCESS CONTROLLED FUNCTIONS
    (Only the yiume team can execute these functions)
    ////////////////////////////////////////////////////////////// */

    /**
     * @notice Reserves tokens to the yiume team
     *         A total number of tokens that can be reserved is limited to `reserveAmount`
     * @param  recipient : which wallet address to receive tokens.
     *                     usually one of the yiume team.
     * @param  amount    : number of tokens to reserve
     */
    function reserve(address recipient, uint256 amount) external onlyOwner {
        require(recipient != address(0), "Zero address");
        require(amount > 0, "Invalid amount");
        require(
            totalSupply() + amount <= maxSupply,
            "Max supply exceeded"
        );
        require(
            tokensReserved + amount <= reserveAmount,
            "Max reserve amount exceeded"
        );

        tokensReserved += amount;

        for (uint256 i = 0; i < amount; i++) {
            _safeMint(recipient, 1);
        }

        emit ReservedToken(msg.sender, recipient, amount);
    }

    /**
     * @notice Withdraw the balance
     */
    function withdraw() external onlyOwner {
        (bool success,) = payable(owner()).call{value : address(this).balance}("");
        require(success, "Transfer failed.");
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

    /**
     * @notice Set a status of sales
     * @param  _status : 0 (NotStarted) / 1 (AllowlistSale) / 2 (PublicSale) / 3 (Finished)
     */
    function setStatus(Status _status) external onlyOwner {
        status = _status;
        emit StatusChanged(_status);
    }

    /**
     * @notice Set a merkle root for allowlist keys
     *         This smart contract uses the merkle tree to verify if the wallet address is included in the allowlist
     * @param  _root : root of the merkle tree of allowlist keys
     */
    function setAllowlistRoot(bytes32 _root) external onlyOwner {
        root = _root;
        emit RootChanged(_root);
    }

    /* ///////////////////////////////////////////////////////////////
    INTERNAL FUNCTIONS
    ////////////////////////////////////////////////////////////// */

    /**
     * @dev Returns a base URI of a token (a link to the metadata folder on Arweave)
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

    /**
     * @notice Returns the number of tokens minted by `owner`
     * @param  owner : wallet address to get the number of tokens minted by
     * @return _numberMinted(owner) : number of tokens minted by the owner
     */
    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    /**
     * @notice Returns the ownership data of a token
     * @param  tokenId: the Id of the token to get the ownership data of
     * @return _ownershipOf(tokenId) : struct data of the owner of the token
               It consists of the following information:
                   addr           : address of the owner
                   startTimestamp : when the owner first minted the token
                   burned         : Whether the token has been burned
     */
    function getOwnershipData(uint256 tokenId)
    external
    view
    returns (TokenOwnership memory)
    {
        return _ownershipOf(tokenId);
    }
}

