// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./Ownable.sol";
import "./ERC721.sol";
import "./IERC2981.sol";
import "./Errors.sol";

/**
 * @dev Contract implementing BRINFT features for NFTPrivateSale
 */
contract BRINFT is Ownable, ERC721, IERC2981 {
    /**
     * @dev Maximum amount of NFTs that a single mint can produce
     */
    uint256 constant MAX_MINT = 5;

    /**
     * @dev royalties amount denominator
     */
    uint256 constant ROYALTIES_DENOMINATOR = 100;

    /**
     * @dev The event emitted when new sale contract address is set
     */
    event NewSaleContract(address indexed saleContract);

    /**
     * @dev The event emitted when new URI base has been set and prices revealed
     */
    event PricesRevealed();

    /**
     * @dev A max cap for all possible mints for the contract
     */
    uint256 mintCap;

    /**
     * @dev Sale contract address allowed to mint new tokens
     */
    address sale;

    /**
     * @dev Admin address contract allowed to burn tokens
     */
    address immutable admin;

    /**
     * @dev Id of the next token that will be minted
     */
    uint256 nextTokenId;

    /**
     * @dev Base URI of all tokens
     */
    string baseURI;

    /**
     * @dev The mapping for tokens prices
     */
    mapping(uint256 => uint256) public price;

    /**
     * @dev The address royalties will be sent to
     */
    address immutable vault;

    /**
     * @dev The royalties size normalized to 1%
     */
    uint256 immutable royalties;

    /**
     * @dev Flag if bulk deposit has been made already
     */
    bool bulkDepositMade;

    /**
     * @dev Flag if prices have been already set
     */
    bool public pricesSet;

    /**
     * @dev The modifier allowing to pass only sale contract caller
     */
    modifier onlySaleContract() {
        if (_msgSender() != sale) revert Restricted();
        _;
    }

    /**
     * @dev The modifier allowing to pass only admin caller
     */
    modifier onlyAdmin() {
        if (_msgSender() != admin) revert Restricted();
        _;
    }

    /**
     * @dev The modifier allowing to pass admin and owner callers only
     */
    modifier onlyAdminOrOwner() {
        if (_msgSender() != admin && _msgSender() != owner()) revert Restricted();
        _;
    }

    /**
     * @dev The contract constructor.
     *
     * @param owner_ The owner of the contract
     * @param admin_ The admin of the contract
     * @param mintCap_ The cap for all tokens possible to be minted in this contract
     * @param name_ The name of the NFT
     * @param symbol_ The symbol for the NFT
     * @param vault_ The vault that will collect royalties
     * @param royalties_ Percentage for all royalties in NFT sale
     * @param baseURI_ The uri base for all NFTs
     */
    constructor(
        address owner_,
        address admin_,
        uint256 mintCap_,
        string memory name_,
        string memory symbol_,
        address vault_,
        uint256 royalties_,
        string memory baseURI_
    ) ERC721(name_, symbol_) Ownable(owner_) {
        if (vault_ == address(0)) revert ZeroAddress();
        if (admin_ == address(0)) revert ZeroAddress();
        mintCap = mintCap_;
        vault = vault_;
        admin = admin_;
        royalties = royalties_;
        baseURI = baseURI_;
    }

    /**
     * @dev The method to reveal all token prices and updated metadata
     *
     * @param baseURI_ New URI to be set
     * @param prices_ Prices of all tokens in the contract
     */
    function reveal(string calldata baseURI_, uint256[] calldata prices_) external onlyAdminOrOwner {
        if (pricesSet) revert AlreadySet();
        pricesSet = true;
        baseURI = baseURI_;
        for (uint256 i = 0; i < prices_.length;) {
            price[i] = prices_[i];
            unchecked {
                ++i;
            }
        }
        emit PricesRevealed();
    }

    /**
     * @dev Setting new sale contract address
     *
     * @param saleContract_ New sale contract address to be set
     */
    function setSaleContract(address saleContract_) external onlyOwner {
        if (sale != address(0)) revert AlreadySet();
        if (saleContract_ == address(0)) revert ZeroAddress();
        sale = saleContract_;
        emit NewSaleContract(sale);
    }

    /**
     * @dev Minting new tokens
     *
     * @param recipent_ Receiver of newly minted tokens
     * @param amount_ The amount of tokens to be minted (maximum 5)
     */
    function mint(address recipent_, uint256 amount_) external onlySaleContract {
        if (amount_ > MAX_MINT) revert TooBig();
        if (recipent_ == address(0)) revert ZeroAddress();

        _mintMany(recipent_, amount_);
    }

    /**
     * @dev Bulk minting tokens
     *
     * @param amount_ Amount of tokens to be minted
     */
    function bulkMint(uint256 amount_) external onlyOwner {
        if (bulkDepositMade) revert Blocked();
        bulkDepositMade = true;
        _mintMany(_msgSender(), amount_);
    }

    /**
     * @dev This contract implements IERC2981 interface.
     *
     * Note: Implemented manualy due to simplified royalty handling in the contract
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721) returns (bool) {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev IERC2981 implementation for royalties
     */
    function royaltyInfo(uint256, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount) {
        return (vault, salePrice * royalties / ROYALTIES_DENOMINATOR);
    }

    /**
     * @dev Burning existing tokens
     *
     * Burning is limited to a specific timeframe and returns a specific amount of tokens
     * to token owner.
     *
     * @param tokenId_ Id of the token to be burnt
     */
    function burn(uint256 tokenId_) external onlySaleContract {
        _burn(tokenId_);
        delete price[tokenId_];
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return baseURI;
    }

    function _mintMany(address recipent_, uint256 amount_) internal {
        if (amount_ > mintCap) revert CapExceeded();

        mintCap -= amount_;
        for (uint256 i = 0; i < amount_;) {
            nextTokenId++;
            // slither-disable-next-line costly-loop
            _safeMint(recipent_, nextTokenId - 1);
            unchecked {
                ++i;
            }
        }
    }
}

