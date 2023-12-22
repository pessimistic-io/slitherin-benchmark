// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC721.sol";
import "./IERC20.sol";
import "./ERC721Enumerable.sol";
import "./ERC721URIStorage.sol";
import "./Ownable.sol";
import "./Counters.sol";

import "./IVRFControllerV2.sol";
import "./IScratchEmTreasury.sol";
import "./ReentrancyGuard.sol";

/// @title Blasting
/// @notice This contract is used to mint NFTs that can be scratched to reveal a prize.
contract Blasting is
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    Ownable,
    ReentrancyGuard
{
    /// @notice This library is used to convert uint256 to string.
    using Strings for uint256;
    /// @notice This library is used to increment the token ID.
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    /// INTERFACES

    IVRFControllerV2 internal supraRouter;

    IScratchEmTreasury internal treasury;

    IERC20 immutable ERC20;
    uint constant DECIMALS = 9;

    /// RNG VARS
    uint256 constant numConfirmations = 1;
    mapping(uint256 => address) nonceToMinterAddress;
    mapping(uint256 => uint256) nonceToRngCount;
    mapping(uint256 => bool) isNonceReverted;
    mapping(uint256 => bool) isNonceGiveaway;

    /// GAME VARS

    uint256 public ticketPrice = 50 * 10 ** DECIMALS; // 10 ERC20
    uint256 public totalTicketCount = 10000;
    uint256 private emptyTickets = 7775;

    uint256 public minMintable = 1;
    uint256 public maxMintable = 15;
    enum CardResult {
        LOSS,
        WIN125,
        WIN250,
        WIN600
    }

    CardResult[] public cardResults = [
        CardResult.LOSS,
        CardResult.WIN125,
        CardResult.WIN250,
        CardResult.WIN600
    ];

    uint internal winVariantCount = 90;
    uint internal lossVariantCount = 90;

    mapping(CardResult => uint) public generationCounts;

    mapping(CardResult => uint) rewardAmounts;

    mapping(uint256 => CardResult) public cardResult;

    mapping(uint256 => uint256) public cardMintedAt;

    mapping(uint256 => bool) public isCardScratched;
    mapping(uint256 => bool) public isCardBalanceClaimed;

    mapping(address => uint256) public userScratchedAllAt;
    mapping(address => uint256) public userClaimedAllAt;

    string internal baseURI =
        "ipfs://bafybeid76pg2kuebzkcprnyaye42d5vgyq532mwtyjwea4xz5k4cbi4bwy/";

    string internal unscratchedURI =
        "ipfs://bafkreicuwcwx6hnth3lpvs3glsqel62cdpvcnydk6xzlpabsiy4ggi3epq/";

    address public stakingPoolAddress = owner();

    uint public stakingPoolCut = 0;

    uint public burnCut = 20;

    uint8 public swapType = 0;

    address[] public path;

    /// EVENTS

    // this event is emitted when a user start minting of a ticket
    event MintStarted(address user, uint256 ticketAmount, uint256 nonce);

    // this event is emitted when minting of a ticket is finished
    event MintFinished(
        address indexed user,
        uint256 ticketAmount,
        uint256 indexed nonce,
        uint256 earnedAmount
    );
    // this event is emitted when a user reverts a mint
    event MintReverted(address user, uint256 nonce, uint256 withdrawnAmount);

    // this event is emitted when a user scratchs a ticket
    event CardRevealed(uint256 tokenId, CardResult cardResult);

    // this event is emitted when a user claims their balance
    event BalanceClaimed(address user, uint256 withdrawnAmount);

    // this event is emitted when a user claims their balance
    event AllCardsClaimed(address user);

    // this event is emitted when a user scratches all their tickets
    event AllCardsScratched(address user);

    // this event is emitted when a user burns all of their burned or 0 reward tickets
    event AllBurned(address user);

    // this event is emitted when the contract owner changes the baseURI
    event BaseURIChanged(string newBaseURI);

    // this event is emitted when the contract owner changes the unscratchedURI
    event UnscratchedURIChanged(string newUnscratchedURI);

    // this event is emitted when the contract owner changes the SupraRouter oracle
    event SupraRouterChanged(IVRFControllerV2 newSupraRouter);

    // this event is emitted when the contract owner changes the ticket price
    event PriceChanged(uint256 newPrice);

    // this event is emitted when the contract owner changes the staking pool address
    event StakingPoolAddressChanged(address newStakingPoolAddress);

    // this event is emitted when the contract owner changes the staking pool cut
    event StakingPoolCutChanged(uint newStakingPoolCut);

    // this event is emitted when the contract owner changes the burn cut
    event BurnCutChanged(uint newBurnCut);

    // this event is emitted when the contract owner changes the swap type
    event SwapTypeChanged(uint8 newSwapType);

    // this event is emitted when the contract owner changes the path
    event PathChanged(address[] newPath);

    /// SWAP ROUTER
    // Universal Router 0x4648a43B2C14Da09FdF82B161150d3F634f40491
    // _router Arbitrum 0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506

    /// VRF
    // Arbitrum Goerli Testnet 0xba6D6F8040efCac740b3C0388D866d3C91f1D6bf
    // Mumbai 0xbfe0c25C43513090b6d3A380E4D77D29fbe31d01

    /// @param _erc20 The playable token contract
    /// @param _supraRouter The SupraRouter contract
    /// @param _treasury The treasury contract
    constructor(
        IERC20 _erc20,
        IVRFControllerV2 _supraRouter,
        IScratchEmTreasury _treasury
    ) ERC721("Blasting", "BLAST") {
        ERC20 = _erc20;
        /** The code below does the following:
         * 1. Creates a mapping which stores the number of cards of each type in the pack.
         * 2. Creates a mapping which stores the reward amount of each type of card.
         * 3. Initializes the mappings with the values.
         */

        generationCounts[CardResult.WIN125] = 1600;
        generationCounts[CardResult.WIN250] = 500;
        generationCounts[CardResult.WIN600] = 125;

        rewardAmounts[CardResult.WIN125] = 125;
        rewardAmounts[CardResult.WIN250] = 250;
        rewardAmounts[CardResult.WIN600] = 600;
        rewardAmounts[CardResult.LOSS] = 0;

        supraRouter = _supraRouter;
        treasury = _treasury;
    }

    /// @notice Get base URI
    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    /// @notice Set base URI
    /// @param _newBaseURI New base URI
    function setBaseURI(string memory _newBaseURI) external onlyOwner {
        baseURI = _newBaseURI;
        emit BaseURIChanged(_newBaseURI);
    }

    /// @notice Set unscratched URI
    /// @param _newUnscratchedURI New unscratched URI
    function setUnscratchedURI(
        string memory _newUnscratchedURI
    ) external onlyOwner {
        unscratchedURI = _newUnscratchedURI;
        emit UnscratchedURIChanged(_newUnscratchedURI);
    }

    /// @notice Set router address
    /// @param _supraRouter New router address
    function setSupraRouter(IVRFControllerV2 _supraRouter) external onlyOwner {
        supraRouter = _supraRouter;
        emit SupraRouterChanged(_supraRouter);
    }

    /// @notice Set treasury address
    /// @param _treasury New treasury address
    function setTreasury(IScratchEmTreasury _treasury) external onlyOwner {
        treasury = _treasury;
    }

    /// @notice Set new price
    /// @param _newPrice New price
    function setPrice(uint256 _newPrice) external onlyOwner {
        ticketPrice = _newPrice;
        emit PriceChanged(_newPrice);
    }

    /// @notice Set minMintable
    /// @param _minMintable New minMintable
    function setMinMintable(uint256 _minMintable) external onlyOwner {
        minMintable = _minMintable;
    }

    /// @notice Set maxMintable
    /// @param _maxMintable New maxMintable
    function setMaxMintable(uint256 _maxMintable) external onlyOwner {
        maxMintable = _maxMintable;
    }

    /// @notice Set new burn cut
    /// @param _newBurnCut New burn cut
    function setBurnCut(uint _newBurnCut) external onlyOwner {
        burnCut = _newBurnCut;
        emit BurnCutChanged(_newBurnCut);
    }

    /// @notice Set new staking pool cut
    /// @param _newStakingPoolCut New staking pool address
    function setStakingPoolCut(uint _newStakingPoolCut) external onlyOwner {
        stakingPoolCut = _newStakingPoolCut;
        emit StakingPoolCutChanged(_newStakingPoolCut);
    }

    /// @notice Set new staking pool address
    /// @param _newStakingPoolAddress New staking pool address
    function setStakingPoolAddress(
        address _newStakingPoolAddress
    ) external onlyOwner {
        stakingPoolAddress = _newStakingPoolAddress;
        emit StakingPoolAddressChanged(_newStakingPoolAddress);
    }

    /// @notice Set new swap type
    /// @param _swapType New swap type
    function setSwapType(uint8 _swapType) external onlyOwner {
        swapType = _swapType;
        emit SwapTypeChanged(_swapType);
    }

    /// @notice Set new path
    /// @param _path New path
    function setPath(address[] memory _path) external onlyOwner {
        path = new address[](_path.length);
        for (uint256 i = 0; i < _path.length; i++) {
            path[i] = _path[i];
        }
        emit PathChanged(_path);
    }

    /// MINTING

    /// @notice Start minting
    /// @param ticketCount Number of tickets to mint
    function startMint(uint8 ticketCount) external nonReentrant {
        /** @dev The code above does the following:
         * 1. Checks that the user is not trying to mint more than 20 or 0 tokens
         * 2. Checks that the user has sufficient allowance to pay for the minting
         * 3. Checks that there are enough tickets left to mint
         * 4. Calls the random number generator contract to generate a request for a random number
         * 5. Stores the user's address, the number of tickets to mint, and the amount of SCRT paid in a map so that the data can be accessed when the random number is generated
         * 6. Emits an event to notify the user that the minting has started and that they should wait for the random number to be generated
         */
        require(
            ticketCount >= minMintable,
            "Can't mint less than minMintable tokens"
        );
        require(
            ticketCount <= maxMintable,
            "Can't mint more than maxMintable tokens"
        );
        uint priceToPay = ticketPrice * ticketCount;
        require(ticketCount < totalTicketCount, "Not enough tickets");

        require(
            ERC20.allowance(msg.sender, address(treasury)) >= priceToPay,
            "Not enough allowance"
        );

        uint256 generated_nonce = supraRouter.generateRequest(ticketCount);

        treasury.nonceLock(
            generated_nonce,
            msg.sender,
            address(ERC20),
            priceToPay
        );

        nonceToMinterAddress[generated_nonce] = msg.sender;
        nonceToRngCount[generated_nonce] = ticketCount;
        emit MintStarted(msg.sender, ticketCount, generated_nonce);
    }

    /// @notice Start minting
    /// @param ticketCount Number of tickets to mint
    function startMintGiveaway(
        uint8 ticketCount,
        address _to
    ) external nonReentrant onlyOwner {
        require(ticketCount < totalTicketCount, "Not enough tickets");

        uint256 generated_nonce = supraRouter.generateRequest(ticketCount);
        isNonceGiveaway[generated_nonce] = true;
        nonceToMinterAddress[generated_nonce] = _to;
        nonceToRngCount[generated_nonce] = ticketCount;
        emit MintStarted(_to, ticketCount, generated_nonce);
    }

    /// @notice Finish minting
    /// @param _nonce Nonce of the minting
    /// @param rngList List of random numbers
    function endMint(uint256 _nonce, uint256[] calldata rngList) public {
        require(
            msg.sender == address(supraRouter),
            "only supra router can call this function"
        );
        if (!isNonceGiveaway[_nonce]) {
            require(!isNonceReverted[_nonce], "Nonce is reverted");
            treasury.nonceUnlock(
                _nonce,
                swapType,
                path,
                burnCut,
                stakingPoolCut,
                address(ERC20),
                stakingPoolAddress
            );
        }
        address to = nonceToMinterAddress[_nonce];
        uint ticketCount = nonceToRngCount[_nonce];
        require(ticketCount < totalTicketCount, "Not enough tickets");
        uint wonAmount = 0;
        for (uint i = 0; i < ticketCount; i++) {
            uint ticketNo = rngList[i] % totalTicketCount;
            uint _ticketLimit = emptyTickets;
            uint resultIndex = 0;
            while (ticketNo > _ticketLimit) {
                resultIndex++;
                _ticketLimit += generationCounts[cardResults[resultIndex]];
            }
            CardResult result = CardResult(resultIndex);
            (string memory uri, uint _wonAmount) = _calculateResult(
                result,
                rngList[i]
            );

            wonAmount += _wonAmount;

            uint256 tokenId = _tokenIdCounter.current();
            cardResult[tokenId] = result;

            _tokenIdCounter.increment();
            cardMintedAt[tokenId] = block.timestamp;
            _safeMint(to, tokenId);
            _setTokenURI(tokenId, uri);
        }
        treasury.gameResult(to, address(ERC20), wonAmount);
        emit MintFinished(to, ticketCount, _nonce, wonAmount);
    }

    /// @notice Calculate the result of the card
    /// @param result The result of the card
    /// @param randomNo The random number
    /// @return uri The uri of the card
    /// @return wonAmount The amount of the card
    function _calculateResult(
        CardResult result,
        uint randomNo
    ) internal returns (string memory uri, uint wonAmount) {
        uint index;
        if (result != CardResult.LOSS) {
            generationCounts[result]--;
            wonAmount = (rewardAmounts[result] * 10 ** DECIMALS);
            index = (randomNo % 10e6) % winVariantCount;
        } else {
            emptyTickets--;
            index = (randomNo % 10e6) % lossVariantCount;
        }
        uri = string(
            abi.encodePacked(
                rewardAmounts[result].toString(),
                "/",
                rewardAmounts[result].toString(),
                "-",
                index.toString(),
                ".json"
            )
        );
        if (totalTicketCount != 0) {
            totalTicketCount--;
        } else {
            revert("No more ticket");
        }
    }

    /// @notice Revert minting of a card
    /// @param _nonce The nonce of the minting
    function revertMint(uint256 _nonce) external nonReentrant {
        require(
            msg.sender == nonceToMinterAddress[_nonce],
            "You are not the minter"
        );
        isNonceReverted[_nonce] = true;
        treasury.nonceRevert(_nonce);
    }

    /// @notice scratch a card
    /// @param tokenId The id of the card
    function scratchCard(uint256 tokenId) public {
        require(ownerOf(tokenId) == msg.sender, "You are not the owner");
        require(!getCardScratched(tokenId), "Card has already been revealed");
        isCardScratched[tokenId] = true;
        emit CardRevealed(tokenId, cardResult[tokenId]);
    }

    /// @notice scratch all cards
    function scratchAllCards() public {
        require(balanceOf(msg.sender) > 0, "You don't have any card");
        userScratchedAllAt[msg.sender] = block.timestamp;
        emit AllCardsScratched(msg.sender);
    }

    /// @notice scratch all cards
    function scratchAllCardsTreasury() external {
        require(msg.sender == address(treasury), "Only treasury can call this");
        userScratchedAllAt[tx.origin] = block.timestamp;
        emit AllCardsScratched(tx.origin);
    }

    /// @notice scratch and claim all cards
    function scratchAndClaimAllCardsTreasury() external {
        require(msg.sender == address(treasury), "Only treasury can call this");
        userScratchedAllAt[tx.origin] = block.timestamp;
        userClaimedAllAt[tx.origin] = block.timestamp;
        emit AllCardsClaimed(tx.origin);
    }

    function _scratchAndClaimAllCards() internal {
        userScratchedAllAt[msg.sender] = block.timestamp;
        userClaimedAllAt[msg.sender] = block.timestamp;
    }

    /// @notice returns the reward of the card
    /// @param tokenId The tokenId of the card
    function getCardReward(uint256 tokenId) external view returns (uint256) {
        if (getCardScratched(tokenId)) {
            return rewardAmounts[cardResult[tokenId]] * 10 ** DECIMALS;
        } else {
            return 0;
        }
    }

    /// @notice returns if the card is scratched
    /// @param tokenId The tokenId of the card
    function getCardScratched(uint256 tokenId) public view returns (bool) {
        if (cardMintedAt[tokenId] > userScratchedAllAt[ownerOf(tokenId)]) {
            return isCardScratched[tokenId];
        } else {
            return true;
        }
    }

    /// @notice returns all the cards that are scratched and not claimed
    /// @param user The address of the user
    function getAllScratchedCards(
        address user
    ) external view returns (uint256[] memory) {
        uint balance = balanceOf(user);
        uint256[] memory tokenIds = new uint256[](balance);
        uint256 counter = 0;
        for (uint256 i = 0; i < balance; i++) {
            uint _tokenId = tokenOfOwnerByIndex(user, i);
            if (getCardScratched(_tokenId) && !getCardClaimed(_tokenId)) {
                tokenIds[counter] = _tokenId;
                counter++;
            }
        }
        return tokenIds;
    }

    /// @notice returns if the card is claimed
    /// @param tokenId The id of the token
    function getCardClaimed(uint256 tokenId) public view returns (bool) {
        if (cardMintedAt[tokenId] > userClaimedAllAt[ownerOf(tokenId)]) {
            return isCardBalanceClaimed[tokenId];
        } else {
            return true;
        }
    }

    /// @notice returns claimed token ids of user
    /// @param user The address of the user
    function getAllClaimedCards(
        address user
    ) external view returns (uint256[] memory) {
        uint balance = balanceOf(user);
        uint256[] memory tokenIds = new uint256[](balance);
        uint256 counter = 0;
        for (uint256 i = 0; i < balance; i++) {
            uint _tokenId = tokenOfOwnerByIndex(user, i);
            if (getCardClaimed(_tokenId)) {
                tokenIds[counter] = _tokenId;
                counter++;
            }
        }
        return tokenIds;
    }

    /// @notice returns owned token ids of user
    /// @param user The address of the user
    function getAllCards(
        address user
    ) external view returns (uint256[] memory) {
        uint balance = balanceOf(user);
        uint256[] memory tokenIds = new uint256[](balance);
        for (uint256 i = 0; i < balance; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(user, i);
        }
        return tokenIds;
    }

    /// @notice burns all claimed or zero reward cards
    function burnAllCardsTreasury() external {
        address user = tx.origin;
        require(msg.sender == address(treasury), "Only treasury can call this");
        uint balance = balanceOf(user);
        for (int i = 0; uint(i) < balance; i++) {
            uint tokenId = tokenOfOwnerByIndex(user, uint(i));
            if (
                getCardScratched(tokenId) &&
                rewardAmounts[cardResult[tokenId]] == 0
            ) {
                _burn(tokenId);
                i--;
                balance--;
            } else if (getCardClaimed(tokenId)) {
                _burn(tokenId);
                i--;
                balance--;
            }
        }
        emit AllBurned(user);
    }

    /// @notice Claim the balance of user
    /// @param tokenId The tokenId of the card
    function claimBalanceByToken(uint tokenId) external nonReentrant {
        require(ownerOf(tokenId) == msg.sender, "You are not the owner");
        if (!getCardScratched(tokenId)) {
            isCardScratched[tokenId] = true;
        }
        require(!getCardClaimed(tokenId), "Balance has already been claimed");
        isCardBalanceClaimed[tokenId] = true;
        uint amount = rewardAmounts[cardResult[tokenId]] * 10 ** DECIMALS;
        require(amount > 0, "No balance to claim");
        treasury.claimRewardsByGame(msg.sender, address(ERC20), amount);
        emit BalanceClaimed(msg.sender, amount);
    }

    /// @notice Withdraw the balance of contract
    /// @param token The address of token
    function withdrawAll(address token) external onlyOwner {
        uint contractBalance = IERC20(token).balanceOf(address(this));
        bool success = IERC20(token).transfer(msg.sender, contractBalance);
        require(success, "Transfer failed");
    }

    /// @notice Withdraw the balance of contract
    function withdrawAllETH() external onlyOwner {
        uint contractBalance = address(this).balance;
        payable(msg.sender).transfer(contractBalance);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
        if (from != address(0) && to != address(0)) {
            revert("Cannot transfer");
        }
    }

    // The following functions are overrides required by Solidity.

    function _burn(
        uint256 tokenId
    ) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        if (getCardScratched(tokenId)) {
            return super.tokenURI(tokenId);
        } else {
            return unscratchedURI;
        }
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

