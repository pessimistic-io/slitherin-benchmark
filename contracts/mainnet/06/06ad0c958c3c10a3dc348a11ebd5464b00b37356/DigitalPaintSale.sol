// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import {AccessControl} from "./AccessControl.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Random} from "./Random.sol";

import {AllowList} from "./AllowList.sol";
import {DigitalPaint} from "./DigitalPaint.sol";

contract DigitalPaintSale is AccessControl, AllowList, ReentrancyGuard {
    using Random for Random.Manifest;

    /// @notice Raised when caller is not an EOA
    error OnlyEOA(address account);
    /// @notice Raised when allowlist sale has ended
    error AllowListSaleClosed();
    /// @notice Raised when public sale has ended
    error PublicSaleClosed();
    /// @notice Raised when caller tries to mint more than the mint cap
    error MintCapExceeded();
    /// @notice Raised when there are insufficient tokens to mint
    error InsufficientSupply();
    /// @notice Raised when caller does not send the correct amount of ETH
    error IncorrectMintPrice();
    /// @notice Raised when caller is not an admin
    error Unauthorized();
    /// @notice Raised when sale has not been initialized
    error SaleNotInitialized();
    /// @notice Raised when attempt made to distribute funds without split being initialized
    error SplitNotInitialized();

    /// @notice Packed little guy for tracking mint status
    struct MintStatus {
        uint128 ac;
        uint128 pp;
    }

    /// @notice Packed little guy who remembers sale times
    struct SaleTimes {
        /// @notice Allow List sale start time: 1676566800 = 2/16/2023 09:00:00 AM PST
        uint128 allowListStart;
        /// @notice Public sale start time: 1676577600 = 2/16/2023 12:00:00 PM PST
        uint128 publicStart;
    }

    /// @notice Access Control role for admin
    bytes32 public constant ADMIN = keccak256("ADMIN");
    /// @notice The total number of tokens for sale
    uint256 public constant TOTAL_SALE_SUPLLY = 4950;
    /// @notice Maximum number of tokens per wallet during allowlist sale
    uint256 public constant ALLOWLIST_MINT_CAP = 3;
    /// @notice Maximum number of tokens per wallet during public sale
    uint256 public constant PUBLIC_MINT_CAP = 2;

    SaleTimes public saleTimes;
    /// @notice DigitalPaint contract
    DigitalPaint public digitalPaint;
    /// @notice Track number of tokens minted
    MintStatus public mintStatus;
    /// @notice Mint price during allowlist sale
    uint256 public allowListMintPrice = 0.1 ether;
    /// @notice Mint price during public sale
    uint256 public publicMintPrice = 0.2 ether;
    /// @notice Track number of tokens minted per wallet during allowlist sale
    mapping(address => uint256) public allowListPurchases;
    /// @notice Track number of tokens minted per wallet during public sale
    mapping(address => uint256) public publicPurchases;
    /// @notice Amount to be paid prior to splitting
    uint256 public topCut;
    /// @notice Amount paid to topCutRecipient
    uint256 public topCutPaid;
    /// @notice Recipient address of topCut
    address payable public topCutReipient;
    /// @notice Address of sale splitter for
    address payable public primarySaleSplitter;

    /// @notice Deck to draw from when (randomly) minting tokens
    Random.Manifest private _acDeck;

    constructor(address[] memory admins) {
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        for (uint256 i = 0; i < admins.length; i++) {
            _setupRole(ADMIN, admins[i]);
        }
        Random.setup(_acDeck, 4950);
    }

    modifier onlyAdmin() {
        if (
            !hasRole(ADMIN, msg.sender) &&
            !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        ) revert Unauthorized();
        _;
    }

    /// @notice Allow accounts on allowlist to mint an Artist Choice token
    /// @param amount The number of tokens to mint
    /// @param proof Merkle proof used to establish that the caller is on the allowlist
    function allowListPurchase(uint256 amount, bytes32[] calldata proof)
        external
        payable
        nonReentrant
    {
        _onlyAllowList();
        _onlyEOA(msg.sender);
        _verifyProof(msg.sender, proof);
        MintStatus memory status = mintStatus;
        if (status.ac + status.pp + amount > TOTAL_SALE_SUPLLY) {
            revert InsufficientSupply();
        }
        if (allowListPurchases[msg.sender] + amount > ALLOWLIST_MINT_CAP) {
            revert MintCapExceeded();
        }
        if (msg.value != amount * allowListMintPrice) {
            revert IncorrectMintPrice();
        }
        allowListPurchases[msg.sender] += amount;
        _randomMint(msg.sender, amount);
    }

    /// @notice Randomly purchase either Artist Choice tokens or Paint Passes
    /// @param amount The number of tokens to mint
    function purchase(uint256 amount) external payable nonReentrant {
        _onlyPublic();
        _onlyEOA(msg.sender);
        if (publicPurchases[msg.sender] + amount > PUBLIC_MINT_CAP) {
            revert MintCapExceeded();
        }
        MintStatus memory status = mintStatus;
        if (status.ac + status.pp + amount > TOTAL_SALE_SUPLLY) {
            revert InsufficientSupply();
        }

        if (msg.value != amount * publicMintPrice) {
            revert IncorrectMintPrice();
        }
        publicPurchases[msg.sender] += amount;
        _randomMint(msg.sender, amount);
    }

    ////////////////////////////////////////////////////////////////////////////
    // ADMIN
    ////////////////////////////////////////////////////////////////////////////

    /// @notice Admin function to initialize the sale
    /// @param _digitalPaint The DigitalPaint contract
    /// @param allowListStart The timestamp when the allowlist sale starts
    /// @param publicStart The timestamp when the public sale starts
    function initializeSale(
        DigitalPaint _digitalPaint,
        uint128 allowListStart,
        uint128 publicStart
    ) external onlyAdmin {
        digitalPaint = _digitalPaint;
        saleTimes = SaleTimes(allowListStart, publicStart);
    }

    /// @notice Admin function to mint tokens as necessary
    /// @param to The address to mint tokens to
    /// @param amount The number of tokens to mint
    function adminMint(address to, uint256 amount)
        external
        onlyAdmin
        nonReentrant
    {
        MintStatus memory status = mintStatus;
        if (status.ac + status.pp + amount > TOTAL_SALE_SUPLLY) {
            revert InsufficientSupply();
        }
        _randomMint(to, amount);
    }

    /// @notice Admin function to set parameters required to distribute funds
    /// @param _topCut The amount to be paid to topCutRecipient prior to splitting
    /// @param _topCutRecipient The recipient address of the top cut
    /// @param _primarySaleSplitter The address of the sale splitter for primary sales
    function initializeSplit(
        uint256 _topCut,
        address payable _topCutRecipient,
        address payable _primarySaleSplitter
    ) external onlyAdmin {
        topCut = _topCut;
        topCutReipient = _topCutRecipient;
        primarySaleSplitter = _primarySaleSplitter;
    }

    /// @notice Admin function to distribute funds from the sale
    /// @dev Until the topCut is paid, the primary sale splitter will not receive any funds
    function distributeFunds() external onlyAdmin nonReentrant {
        if (
            topCut == 0 ||
            topCutReipient == address(0) ||
            primarySaleSplitter == address(0)
        ) {
            revert SplitNotInitialized();
        }
        // First take care of topCut
        if (topCutPaid < topCut) {
            uint256 amount = topCut - topCutPaid;
            if (amount > address(this).balance) {
                amount = address(this).balance;
            }
            topCutPaid += amount;
            (bool topSplitSuccess, ) = topCutReipient.call{value: amount}("");
            require(topSplitSuccess);
        }
        // Then send the rest to the primary sale splitter
        (bool success, ) = primarySaleSplitter.call{
            value: address(this).balance
        }("");
        require(success);
    }

    /// @notice Admin function to set the allowlist merkle root
    /// @param _merkleRoot The new merkle root
    function setMerkleRoot(bytes32 _merkleRoot) external onlyAdmin {
        _setMerkleRoot(_merkleRoot);
    }

    ////////////////////////////////////////////////////////////////////////////
    // INTERNAL GUYS
    ////////////////////////////////////////////////////////////////////////////

    /// @dev Revert if the account is a smart contract. Does not protect against calls from the constructor.
    /// @param account The account to check
    function _onlyEOA(address account) internal view {
        if (msg.sender != tx.origin || account.code.length > 0) {
            revert OnlyEOA(account);
        }
    }

    /// @notice Verify that allowlist sale is active
    function _onlyAllowList() internal view {
        SaleTimes memory times = saleTimes;
        if (times.allowListStart == 0) revert SaleNotInitialized();
        if (
            block.timestamp < times.allowListStart ||
            block.timestamp >= times.publicStart
        ) revert AllowListSaleClosed();
    }

    /// @notice Verify that public sale is active
    function _onlyPublic() internal view {
        SaleTimes memory times = saleTimes;
        if (times.publicStart == 0) revert SaleNotInitialized();
        if (block.timestamp < times.publicStart) revert PublicSaleClosed();
    }

    /// @notice Randomly mint @param amount Artist Choice or Paint Pass tokens
    function _randomMint(address to, uint256 amount) internal {
        bytes32 seed = Random.random();
        uint256 tokenId;
        MintStatus memory status = mintStatus;
        uint128 ppToMint;

        // Determine random mints:
        for (uint256 i = 0; i < amount; i++) {
            seed = keccak256(abi.encodePacked(seed, i));
            tokenId = _acDeck.draw(seed) + 1;

            if (tokenId <= 100) {
                digitalPaint.transferFrom(address(this), to, tokenId);
                status.ac++;
            } else {
                ppToMint++;
            }
        }

        if (ppToMint > 0) {
            digitalPaint.mint(to, ppToMint);
            status.pp += ppToMint;
        }

        mintStatus = status;
    }
}

