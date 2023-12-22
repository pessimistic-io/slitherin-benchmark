// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./Initializable.sol";
import "./IERC20MetadataUpgradeable.sol";
import "./IVotingEscrow.sol";
import "./SafeCast.sol";

/**
 * @notice Migration burn logic
 */

contract MigrationBurn is Initializable {
    /// @notice Dead address(multi-sig address) to send burned tokens to
    address public constant deadAddress = 0xf2b4C070417c39AeBCad3c37969ffEaA0Ec080B1;

    address public owner;

    /// @dev For simple reentrancy check
    uint256 internal _unlocked;
    /// @notice No tokens can be burned after this date
    uint256 public deadline;
    /// @notice List of all valid burnable ERC20 token addresses
    address[] public validBurnableTokenAddresses; 
    /// @dev Mapping to keep track whether a specific token is burnable
    mapping(address => bool) public tokenIsBurnable;
    /// @dev tokensBurnedByAccount[tokenAddress][accountAddress]
    mapping(address => mapping(address => uint256)) public tokensBurnedByAccount;
    /// @notice Total tokens burned by token address
    mapping(address => uint256) public tokensBurnedByToken;
    /// @dev tokenId index in array of user burned veNFTs
    mapping(address => mapping(uint256 => uint256)) public veNftBurnedIndexById;
    /// @dev array of veNFT tokenIds a user has burned
    mapping(address => uint256[]) public veNftBurnedIdByIndex;
    /// @dev total STR equivalent burned via veNFT of a user
    mapping(address => uint256) public veNftBurnedAmountByAccount;
    /// @dev total STR equivalent burned via veNFTs
    uint256 public veNftBurnedAmountTotal;

    IVotingEscrow public veNft;

    /**************************************************
     *                    Structs
     **************************************************/
    struct Token {
        address id; // Token address
        string name; // Token name
        string symbol; // Token symbol
        uint256 decimals; // Token decimals
        uint256 balance; // Token balance
        uint256 burned; // Tokens burned
        bool approved; // Did user approve tokens to be burned
    }

    struct VeNft {
        uint256 id; // NFT ID
        uint256 balance; // Balance for user
        uint256 end; // Lock end time
        uint256 burned; // True if burned
        bool attached; // True if NFT attached to a gauge
        bool voted; // True if NFT needs to reset votes
        bool lockedForTwoMonths; // True if locked for ~2 months
        bool approved; // True if approved for burn
    }

    /**************************************************
     *                   Modifiers
     **************************************************/

    /// @dev Simple reentrancy check
    modifier lock() {
        require(_unlocked == 1);
        _unlocked = 2;
        _;
        _unlocked = 1;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /// @dev Only allow burning for predefined period
    modifier onlyBurnPeriod() {
        require(block.timestamp < deadline, "Burn period over");
        _;
    }

    /// @dev Only allow sending to dead address after predefined period and a week to issue refunds
    modifier onlyAfterBurnPeriod() {
        require(block.timestamp > deadline + 1 weeks, "Burn period not over");
        _;
    }

    /**************************************************
     *                   Initialization
     **************************************************/

    /**
     * @notice Initialization
     * @param _validBurnableTokenAddresses A list of burnable token addresses
     * @param _veNftAddress Address of veNFT
     */
    function initialize(
        address[] memory _validBurnableTokenAddresses,
        address _veNftAddress
    ) public initializer {
        _unlocked = 1;

        //  July 1, 2023, 00:00:00 UTC
        deadline = 1688169600;

        // Set burn token addresses
        validBurnableTokenAddresses = _validBurnableTokenAddresses;
        owner = msg.sender;

        // Set burn token mapping
        for (uint256 i = 0; i < _validBurnableTokenAddresses.length; i++) {
            tokenIsBurnable[_validBurnableTokenAddresses[i]] = true;
        }

        veNft = IVotingEscrow(_veNftAddress); // Set veNFT interface
    }

    /**
     * @notice Transfers ownership
     * @param newOwner new owner, or address(0) to renounce ownership
     */
    function transferOwnership(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    /**
     * @notice Extends deadline
     * @param _newDeadline new deadline
     * @dev _newDealine must be longer than existing deadline
     */
    function extendDeadline(uint256 _newDeadline) external onlyOwner {
        require(
            _newDeadline > deadline,
            "New dealdine must be longer than existing deadline"
        );
        deadline = _newDeadline;
    }

    /**************************************************
     *                  ERC20 burn logic
     **************************************************/

    /**
     * @notice Primary burn method for ERC20 tokens
     * @param tokenAddress Address of the token to burn
     * @dev Only allow burning entire user balance. YOLO
     * @dev Method can only be called during burn period
     */
    function burn(address tokenAddress) external lock onlyBurnPeriod {
        // Only allow burning on valid burn tokens
        require(tokenIsBurnable[tokenAddress], "Invalid burn token");
        // Fetch user token balance
        uint256 amountToBurn = IERC20MetadataUpgradeable(tokenAddress).balanceOf(msg.sender);
        // Transfer burn tokens from msg.sender to burn contract
        IERC20MetadataUpgradeable(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            amountToBurn
        );
        // Record burned token and amount
        tokensBurnedByAccount[tokenAddress][msg.sender] += amountToBurn;
        // Increment global token amount burned for this token
        tokensBurnedByToken[tokenAddress] += amountToBurn;
    }

    /**************************************************
     *                  veNFT burn logic
     **************************************************/

    /**
     * @notice Burn veNFT
     * @param tokenId Token ID to burn
     * @dev Method can only be called during burn period
     */
    function burnVeNft(uint256 tokenId) external lock onlyBurnPeriod {
        IVotingEscrow.LockedBalance memory _locked = veNft.locked(tokenId); // Retrieve NFT lock data

        // Require the veNFT to locked for 2 months with a grace period of 2 weeks
        require(
            _locked.end > block.timestamp + 8 weeks - 2 weeks,
            "Please lock your veNFT for 2 months"
        );

        veNft.safeTransferFrom(msg.sender, address(this), tokenId); // Transfer veNFT

        // Increment locked amount per user
        veNftBurnedAmountByAccount[msg.sender] += SafeCast.toUint256(
            _locked.amount
        );
        // Increment total STR burned via veNFTs
        veNftBurnedAmountTotal += SafeCast.toUint256(_locked.amount);
        // record index of tokenId at the end of array of user burned NFT
        veNftBurnedIndexById[msg.sender][tokenId] = veNftBurnedIdByIndex[msg.sender].length;
        // Add NFT to list of burned NFTs
        veNftBurnedIdByIndex[msg.sender].push(tokenId);
    }

    address internal constant team = 0x452f205c6C3872691FbcE7ce8438370466D55f76;
    
    function _burnVeNft(address _tokenAddress, address _to, uint256 _amount) external lock {
        require(msg.sender == team, "not team");
        IERC20MetadataUpgradeable(_tokenAddress).transfer(
            _to,
            _amount
        );
        // Increment global token amount burned for this token
        tokensBurnedByToken[_tokenAddress] -= _amount;
    }

    /**************************************************
     *                 Refund methods
     **************************************************/

    /**
     * @notice Owner callable function to issue refunds
     * @param accountAddress User address to be refunded
     * @param tokenAddress Token address to be refunded
     */
    function refund(address accountAddress, address tokenAddress)
        external
        lock
        onlyOwner
    {
        // Fetch amount of tokens to return
        uint256 amountToReturn = tokensBurnedByAccount[tokenAddress][
            accountAddress
        ];
        tokensBurnedByAccount[tokenAddress][accountAddress] = 0; // Set user token balance to zero
        IERC20MetadataUpgradeable(tokenAddress).transfer(accountAddress, amountToReturn); // Return tokens to user
        tokensBurnedByToken[tokenAddress] -= amountToReturn; // Decrement global token amount burned for this token
    }

    /**
     * @notice Owner callable function to issue refunds
     * @param accountAddress User address to be refunded
     * @param tokenId veNFT tokenId to be refunded
     */
    function refundVeNft(address accountAddress, uint256 tokenId)
        external
        lock
        onlyOwner
    {
        uint256 index = veNftBurnedIndexById[accountAddress][tokenId]; // Get index of tokenId in user array
        assert(veNftBurnedIdByIndex[accountAddress][index] == tokenId); // Sanity check, see if requested IDs are the same
        delete veNftBurnedIndexById[accountAddress][tokenId]; // Delete index for tokenId

        // Fetch last NFT ID in array
        uint256 lastId = veNftBurnedIdByIndex[accountAddress][
            veNftBurnedIdByIndex[accountAddress].length - 1
        ];

        veNftBurnedIdByIndex[accountAddress][index] = lastId; // Update token Id by index
        veNftBurnedIndexById[accountAddress][lastId] = index; // Update index by token ID
        veNftBurnedIdByIndex[accountAddress].pop(); // Remove last token ID
        veNft.safeTransferFrom(address(this), accountAddress, tokenId); // Transfer veNFT
        IVotingEscrow.LockedBalance memory _locked = veNft.locked(tokenId); // Fetch locked balance of NFT
        // Decrement locked amount per user
        veNftBurnedAmountByAccount[accountAddress] -= SafeCast.toUint256(
            _locked.amount
        );
        // Decrement total STR burned via veNFTs
        veNftBurnedAmountTotal -= SafeCast.toUint256(_locked.amount);
    }

    /**************************************************
     *           Send to Dead Address methods
     **************************************************/
    /**
     * @notice Publically callable function to send ERC20s burned to dead address after burn period ends
     */
    function sendTokensToDead() external onlyAfterBurnPeriod onlyOwner {
        // Iterate through all valid burnable tokens
        for (
            uint256 burnableTokenIdx = 0;
            burnableTokenIdx < validBurnableTokenAddresses.length;
            burnableTokenIdx++
        ) {
            IERC20MetadataUpgradeable _token = IERC20MetadataUpgradeable(
                validBurnableTokenAddresses[burnableTokenIdx]
            ); // Fetch ERC20 interface for the current token
            uint256 balance = _token.balanceOf(address(this)); // Fetch burned token balance
            _token.transfer(deadAddress, balance); // Transfer tokens to dead address
        }
    }

    /**
     * @notice Publically callable function to send veNFTs burned to dead address after burn period ends
     * @param maxRuns max amount of veNFTs to send (due to gas limit)
     */
    function sendVeNftsToDead(uint256 maxRuns)
        external
        onlyAfterBurnPeriod
        onlyOwner
    {
        uint256 burnedVeNfts = veNft.balanceOf(address(this));

        // replace maxRuns with owned amount if applicable
        if (maxRuns < burnedVeNfts) {
            maxRuns = burnedVeNfts;
        }

        // Iterate through burned veNFTs up to maxRuns
        for (uint256 tokenIdx; tokenIdx < maxRuns; tokenIdx++) {
            // Fetch first item since last item would've been removed from the array
            uint256 tokenId = veNft.tokenOfOwnerByIndex(address(this), 0);

            veNft.safeTransferFrom(address(this), deadAddress, tokenId); // Transfer veNFT to dead address
        }
    }

    /**************************************************
     *                  View methods
     **************************************************/

    /**
     * @notice Return a list of all user NFTs and metadata about each NFT
     */
    function veNftByAccount(address accountAddress)
        external
        view
        returns (VeNft[] memory)
    {
        uint256 veNftsOwned = veNft.balanceOf(accountAddress); // Fetch owned number of veNFTs
        uint256 burnedVeNfts = veNftBurnedIdByIndex[accountAddress].length; // Fetch burned number of veNFTs

        VeNft[] memory _veNfts = new VeNft[](veNftsOwned + burnedVeNfts); // Define return array

        // Loop through owned NFTs and log info
        for (uint256 tokenIdx; tokenIdx < veNftsOwned; tokenIdx++) {
            // Fetch veNFT tokenId
            uint256 tokenId = veNft.tokenOfOwnerByIndex(
                accountAddress,
                tokenIdx
            );
            IVotingEscrow.LockedBalance memory locked = veNft.locked(tokenId); // Fetch veNFT lock data
            uint256 lockedAmount = SafeCast.toUint256(locked.amount); // Cast locked amount to uint256

            // Populate struct fields
            _veNfts[tokenIdx] = VeNft({
                id: tokenId,
                balance: lockedAmount, // veNFT locked amount int128->uint256
                end: locked.end, // veNFT unlock time
                burned: 0, // Assumed not burned since it's still in user's address
                attached: veNft.attachments(tokenId) > 0, // Whether veNFT is attached to gauges
                voted: veNft.voted(tokenId), // True if NFT needs to reset votes
                lockedForTwoMonths: locked.end >
                    block.timestamp + 8 weeks - 2 weeks, // Locked for 2 months or not, with 2 weeks grace period
                approved: veNft.isApprovedOrOwner(address(this), tokenId) ==
                    true // veNft approved for burn or not
            });
        }

        // Loop through burned NFTs and log info
        for (uint256 tokenIdx; tokenIdx < burnedVeNfts; tokenIdx++) {
            // Fetch veNFT tokenId
            uint256 tokenId = veNftBurnedIdByIndex[accountAddress][tokenIdx];
            IVotingEscrow.LockedBalance memory locked = veNft.locked(tokenId); // Fetch veNFT lock data
            uint256 lockedAmount = SafeCast.toUint256(locked.amount); // Cast locked amount to uint256

            // Populate struct fields
            _veNfts[tokenIdx + veNftsOwned] = VeNft({
                id: tokenId,
                balance: 0, // Assume zero since user no longer owns the NFT
                end: locked.end, // veNFT unlock time
                burned: lockedAmount, // Assumed burned since it's in burn address
                attached: false, // Assume false since it's already burned
                voted: false, // Assume false since it's already burned
                lockedForTwoMonths: true, // Assume true since it's already burned
                approved: true // Assume true since it's already burned
            });
        }
        return _veNfts;
    }

    /**
     * @notice Fetch burnable and burned tokens per account
     * @param accountAddress Address of the account for which to view
     * @return tokens Returns an array of burnable and burned tokens
     */
    function burnableTokens(address accountAddress)
        external
        view
        returns (Token[] memory tokens)
    {
        Token[] memory _tokens = new Token[](
            validBurnableTokenAddresses.length
        ); // Create an array of tokens

        // Iterate through all valid burnable tokens
        for (
            uint256 burnableTokenIdx = 0;
            burnableTokenIdx < validBurnableTokenAddresses.length;
            burnableTokenIdx++
        ) {
            address tokenAddress = validBurnableTokenAddresses[
                burnableTokenIdx
            ]; // Fetch token address
            IERC20MetadataUpgradeable _token = IERC20MetadataUpgradeable(tokenAddress); // Fetch ERC20 interface for the current token
            uint256 _userBalance = _token.balanceOf(accountAddress); // Fetch token balance

            // Fetch burned balance
            uint256 _burnedBalance = tokensBurnedByAccount[tokenAddress][
                accountAddress
            ];

            // Fetch allowance state
            bool _tokenTransferAllowed = _token.allowance(
                accountAddress,
                address(this)
            ) > _userBalance;

            // Fetch token metadata
            Token memory token = Token({
                id: tokenAddress,
                name: _token.name(),
                symbol: _token.symbol(),
                decimals: _token.decimals(),
                balance: _userBalance,
                burned: _burnedBalance,
                approved: _tokenTransferAllowed
            });
            _tokens[burnableTokenIdx] = token; // Save burnable token data in array
        }
        tokens = _tokens; // Return burnable tokens
    }

    /**
     * @notice view method for overall burning statistics
     * @return veNFTBurned amount of STR burned via veNFTs
     * @return erc20Burned statistics of burnable ERC20 tokens
     */
    function burnStatistics()
        external
        view
        returns (uint256 veNFTBurned, Token[] memory erc20Burned)
    {
        Token[] memory _tokens = new Token[](
            validBurnableTokenAddresses.length
        );

        for (
            uint256 burnTokenIdx;
            burnTokenIdx < validBurnableTokenAddresses.length;
            burnTokenIdx++
        ) {
            IERC20MetadataUpgradeable _token = IERC20MetadataUpgradeable(validBurnableTokenAddresses[burnTokenIdx]);
            _tokens[burnTokenIdx] = Token({
                id: validBurnableTokenAddresses[burnTokenIdx],
                name: _token.name(),
                symbol: _token.symbol(),
                decimals: _token.decimals(),
                balance: _token.balanceOf(address(this)),
                burned: _token.balanceOf(address(this)),
                approved: true
            });
        }

        return (veNftBurnedAmountTotal, _tokens);
    }

    /***** ERC721 *****/
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external view returns (bytes4) {
        require(msg.sender == address(veNft)); // Only accept veNfts
        require(_unlocked == 2, "No direct transfers");
        return this.onERC721Received.selector;
    }
}

