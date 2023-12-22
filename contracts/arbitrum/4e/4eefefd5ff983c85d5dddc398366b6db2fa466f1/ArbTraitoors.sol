// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;
import {ERC721AQueryableEnumerableMetadata} from "./ERC721AQueryableEnumerableMetadata.sol";
import {Paid} from "./Paid.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {TwoStepOwnable} from "./TwoStepOwnable.sol";

contract ArbTraitoors is 
    ERC721AQueryableEnumerableMetadata, 
    ReentrancyGuard,
    Paid 
{
    /// @notice Revert with an error if mint exceeds the max supply.
    error MintQuantityExceedsMaxSupply(uint256 total, uint256 maxSupply);
    /// @notice Revert with an error if mint quantity exceeds the max per transaction limit.
    error MintQuantityExceedsTransactionLimit(uint256 quantity, uint256 limit);
    /// @notice Revert with error if transfer fails in withdraw
    error WithdrawTransferFailed();
    

    uint256 public constant price = 0.005 ether;

    uint256 public constant maxPerTX = 10;

    constructor(
        string memory name_, 
        string memory symbol_, 
        uint initMintAmount_, 
        uint maxSupply_,
        string memory baseURI_,
        string memory contractURI_
    )
        ERC721AQueryableEnumerableMetadata(name_, symbol_)
    {        
        _maxSupply = maxSupply_;
        _tokenBaseURI = baseURI_;
        _contractURI = contractURI_;

        if (initMintAmount_ > 0)
            _mintERC2309(msg.sender, initMintAmount_);
    }

    function nextTokenId() external view returns(uint) {
        return _currentIndex;
    }

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        string memory baseURI__ = _baseURI();
        return bytes(baseURI__).length != 0 ? 
            string(abi.encodePacked(baseURI__, _toString(tokenId), ".json")) : 
            '';
    }

    // =============================================================
    //                       MINTING INTERFACE
    // =============================================================

    /**
     * @dev Unfiltered paid open mint 
     * - 'mint'
     * - use this to mint as many as possible for the eth sent
     * - more eth => more mints => eth / OPEN_MINT_PRICE quantity
     */
    function mint() external payable {
        if (msg.value < price) 
            revert IncorrectPayment(msg.value, price);
        _mintGuard(msg.sender, msg.value / price);
    }

    /**
     * @dev Unfiltered paid open mint 
     * - 'batch mint'
     * - the parameter is QUANTITY not TOKEN ID
     * - be sure to send `price` * quantity eth 
     * - max of `maxPerTX` quantity per transaction
     */
    function mint(uint quantity_) external payable onlyPaid(price * quantity_) {
        _mintGuard(msg.sender, quantity_);
    }

    /**
     * @dev Use this if you are code, so we can talk
     * - second parameter is QUANTITY not TOKENID
     * - be sure to send `price` * quantity eth 
     * - max of `maxPerTX` quantity per transaction
     */
    function safeMint(
        address to_, 
        uint quantity_
    )
        external payable 
        onlyPaid(price * quantity_)
    {
        _safeMintGuard(to_, quantity_, "");
    }
    
    /**
     * @dev Use this if you are on-chain code, so we can talk
     * - second parameter is QUANTITY not TOKENID
     * - be sure to send `price` * quantity eth 
     * - max of `maxPerTX` quantity per transaction
     */
    function safeMintTo(
        address to_, 
        uint quantity_, 
        bytes memory data_
    )
        external payable 
        onlyPaid(price * quantity_)
    {
        _safeMintGuard(to_, quantity_, data_);
    }


    // =============================================================
    //                      OWNER EXTERNAL INTERFACE
    // =============================================================

    /**
     * Owner only fee mints
     */
    function freeMint(address to_, uint quantity_) external payable onlyOwner {
        _safeMintGuard(to_, quantity_, "");        
    }

    /**
     * For the owner to get paaaid
     * - tips appreciated, the owner is a poor still
     */
    function withdraw() external onlyOwner {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        if(!success)
            revert WithdrawTransferFailed();
    }
    
    // =============================================================
    //                      INTERNAL MINT GUARDS
    // =============================================================

    /**
     * All non-'safe' mints are routed through these functions
     * - use this is you are a human making the transaction
     * - enforces max supply limit
     * - enforces mint phase start
     * - enforces max transaction limit
     */
    function _mintGuard(
        address to_, 
        uint quantity_
    ) internal {
        if(totalSupply() + quantity_ > maxSupply())
            revert MintQuantityExceedsMaxSupply(totalSupply(), maxSupply());
        if(quantity_ > maxPerTX)
            revert MintQuantityExceedsTransactionLimit(quantity_, maxPerTX);

        _mint(to_, quantity_);
    }

    /**
     * All 'safe' mints are routed through these functions
     * - enforces max supply limit
     * - enforces mint phase start
     * - enforces max transaction limit
     */
    function _safeMintGuard(
        address to_, 
        uint quantity_, 
        bytes memory data_
    ) internal {
        if(totalSupply() + quantity_ > maxSupply())
            revert MintQuantityExceedsMaxSupply(totalSupply(), maxSupply());
        if(quantity_ > maxPerTX)
            revert MintQuantityExceedsTransactionLimit(quantity_, maxPerTX);

        _safeMint(to_, quantity_, data_);
    }
}
