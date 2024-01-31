pragma solidity ^0.8.10;

import {Strings} from "./Strings.sol";
import {Owned} from "./Owned.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {ERC20} from "./ERC20.sol";
import {ERC721A} from "./ERC721A.sol";

/// @title WeirdApeYachtClub
/// @notice ERC721A implementation for Weird Ape Yacht Club collection
contract WeirdApeYachtClub is Owned, ERC721A {
    /*///////////////////////////////////////////////////////////////
                                LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using Strings for uint256;
    using SafeTransferLib for ERC20;

    /*///////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error MintIsNotEnabled();
    error MaxMintsReached();
    error InsufficientMintValue();

    /*///////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Max number of mints allowed.
    uint256 private constant MAX_SUPPLY = 10000;

    /// @notice Signals if mint is enabled.
    bool public mintEnabled;
    /// @notice Base URI for token metadata.
    string public baseURI;
    /// @notice Recipient address of the mint costs.
    address payable public recipient;
    /// @notice Mint price per token.
    uint256 public mintPrice;
    /// @notice Mint start after this timestamp.
    uint256 public mintStartTime;

    /*///////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the token metadata URI by id.
    /// @param tokenId The id of the token to return URI from.
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        return string(abi.encodePacked(baseURI, tokenId.toString(), ".json"));
    }

    /*///////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        uint256 mintStartTime_,
        uint256 mintPrice_,
        address payable recipient_
    ) Owned(msg.sender) ERC721A("Weird Ape Yacht Club", "WAYC") {
        mintStartTime = mintStartTime_;
        mintPrice = mintPrice_;
        recipient = recipient_;
        mintEnabled = true;
    }

    /*///////////////////////////////////////////////////////////////
                             USER ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mints an amount of tokens to a given account.
    /// @dev Sends ETH directly to recipient address.
    /// @param to Recipient account of the token.
    /// @param quantity Amount of tokens to mint.
    function mint(address to, uint256 quantity) external payable {
        if (!mintEnabled || block.timestamp < mintStartTime)
            revert MintIsNotEnabled();
        if (_totalMinted() + quantity > MAX_SUPPLY) revert MaxMintsReached();
        if (msg.value < mintPrice * quantity) revert InsufficientMintValue();

        _safeMint(to, quantity);
        SafeTransferLib.safeTransferETH(recipient, msg.value);
    }

    /*///////////////////////////////////////////////////////////////
                            ADMIN ACTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Allows the owner to enable / disable the mint (disabled by default).
    /// @param status New status of the mint.
    function setMintEnabled(bool status) external onlyOwner {
        mintEnabled = status;
    }

    /// @notice Allows the owner to change the recipient address of the mint costs.
    /// @param account New recipient address.
    function setRecipient(address payable account) external onlyOwner {
        recipient = account;
    }

    /// @notice Allows the owner to set a new timestamp for the start of the mint.
    /// @param timestamp The new mint start timestamp.
    function setMintStartTime(uint256 timestamp) external onlyOwner {
        mintStartTime = timestamp;
    }

    /// @notice Allows the owner to set a new mint price.
    /// @param price New mint price per token.
    function setMintPrice(uint256 price) external onlyOwner {
        mintPrice = price;
    }

    /// @notice Allows the owner to set a new base for token URIs.
    /// @param baseURI_ New base URI.
    function setBaseURI(string memory baseURI_) external onlyOwner {
        baseURI = baseURI_;
    }

    /// @notice Allows the owner to withdraw ETH sent to the contract.
    /// @dev Returns the withdrawn amount.
    /// @param to Recipient address of the ETH.
    function recoverETH(address payable to)
        external
        onlyOwner
        returns (uint256 amount)
    {
        amount = address(this).balance;
        SafeTransferLib.safeTransferETH(to, amount);
    }

    /// @notice Allows the owner to withdraw any ERC20 sent to the contract.
    /// @dev Returns the withdrawn amount.
    /// @param token Token to withdraw.
    /// @param to Recipient address of the tokens.
    function recoverTokens(ERC20 token, address to)
        external
        onlyOwner
        returns (uint256 amount)
    {
        amount = token.balanceOf(address(this));
        token.safeTransfer(to, amount);
    }
}
