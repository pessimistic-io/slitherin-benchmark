//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Ownable.sol";
import "./ERC721.sol";
import "./ERC20.sol";

/// Local imports
import "./VRFv2ConsumerTest.sol";

/**
 * @title NFTLootbox
 * @notice A smart contract for creating and managing lootboxes containing NFTs and USD prizes.
 * Players can participate in the lootbox game by paying a fee and have a chance to win NFTs or USD prizes.
 * The contract uses Chainlink VRF (Verifiable Random Function) to generate random numbers for determining the winners.
 */
contract NFTLootboxTest is Ownable {
    struct Lootbox {
        uint256 finishTs;
        uint256 priceForPlay;
        NFT[] nftTokens;
        uint256[] usdPrizes;
        uint256[] probabilities;
        string name;
    }

    struct NFT {
        address contractAddress;
        uint256 tokenId;
        uint256 tokenPrice;
    }

    struct BetDetail {
        uint256 betNum;
        uint256 lootboxId;
        uint256 randomNumRequestId;
    }

    ERC20 public betCoin;
    VRFv2ConsumerTest public vrfV2Consumer;
    uint256 public lastLootboxId;

    mapping(uint256 => Lootbox) public lootboxes;
    mapping(address => BetDetail) public betDetails;

    event LootboxCreated(
        uint256 _priceForPlay,
        uint256 indexed _lootboxId,
        uint256 _finishTS,
        string _name,
        NFT[] nfts,
        uint256[] prizes,
        uint256[] probabilities
    );
    event Play(
        address indexed _player,
        uint256 _timestamp,
        uint256 _priceForPlay,
        uint256 indexed _lootboxId
    );
    event TakedNft(
        address indexed _user,
        address contractAddress,
        uint256 _tokenId,
        uint256 indexed _lootboxId,
        uint256 _timeStamp,
        uint256 _nftPrice
    );
    event TakedUsd(
        address indexed _user,
        uint256 _amount,
        uint256 _timeStamp,
        uint256 indexed _lootboxId
    );

    /**
     * @dev Constructor function
     * @param _betCoin The address of the ERC20 token used for betting
     * @param _vrfV2Consumer The address of the new VRFv2ConsumerTest contract
     */
    constructor(address _betCoin, address _vrfV2Consumer) {
        require(_betCoin != address(0), "Invalid address");
        require(_vrfV2Consumer != address(0), "Invalid address");
        betCoin = ERC20(_betCoin);
        vrfV2Consumer = VRFv2ConsumerTest(_vrfV2Consumer);
    }

    /**
     * @dev Changes the address of the VRFv2ConsumerTest contract
     * @param _vrfV2Consumer The address of the new VRFv2ConsumerTest contract
     */
    function changeVrfV2Consumer(address _vrfV2Consumer) external onlyOwner {
        require(_vrfV2Consumer != address(0), "Invalid address");
        vrfV2Consumer = VRFv2ConsumerTest(_vrfV2Consumer);
    }

    /**
     * @dev Changes the address of the ERC20 token used for betting
     * @param _betCoin The address of the new ERC20 token
     */
    function changebetCoin(address _betCoin) external onlyOwner {
        require(_betCoin != address(0), "Invalid address");
        betCoin = ERC20(_betCoin);
    }

    /**
     * @dev Creates a new lootbox with the specified parameters
     * @param _priceForPlay The price in betCoin to play the lootbox
     * @param _duration The duration of the lootbox in seconds
     * @param _name The name of the lootbox
     * @param nfts An array of NFTs to be included in the lootbox
     * @param prizes An array of USD prizes to be included in the lootbox
     * @param _probabilities An array of probabilities corresponding to the NFTs and USD prizes.
     * Each number in the array represents the probability of winning the corresponding prize and is
     * expressed as a value between 1 and 100000.
     * The range of 1-100000 corresponds to a probability range of 0.001% to 100%, where a higher number
     * indicates a higher probability of winning the associated prize.
     */
    function createLootbox(
        uint256 _priceForPlay,
        uint256 _duration,
        string memory _name,
        NFT[] memory nfts,
        uint256[] memory prizes,
        uint256[] memory _probabilities
    ) external onlyOwner {
        require(nfts.length + prizes.length > 0, "At least one prize required");
        require(
            nfts.length + prizes.length == _probabilities.length,
            "Incorrect probabilities count"
        );
        uint256 maxProbability;
        for (uint256 i; i < _probabilities.length; i++) {
            maxProbability += _probabilities[i];
        }
        require(maxProbability <= 100000, "Incorrect sum of probabilities");
        lastLootboxId++;
        Lootbox storage loot = lootboxes[lastLootboxId];
        for (uint256 i; i < nfts.length; i++) {
            ERC721 tokenAddress = ERC721(nfts[i].contractAddress);
            tokenAddress.transferFrom(
                msg.sender,
                address(this),
                nfts[i].tokenId
            );
            loot.nftTokens.push(nfts[i]);
        }
        loot.usdPrizes = prizes;
        loot.probabilities = _probabilities;
        loot.priceForPlay = _priceForPlay;
        loot.name = _name;
        loot.finishTs = block.timestamp + _duration;
        emit LootboxCreated(
            _priceForPlay,
            lastLootboxId,
            loot.finishTs,
            _name,
            nfts,
            prizes,
            _probabilities
        );
    }

    /**
     * @dev Allows a player to participate in a lootbox game
     * Players need to pay the priceForPlay in betCoin to play the lootbox.
     * If they win, they will receive a randomly selected NFT or a USD prize.
     * @param _lootboxId The ID of the lootbox to play.
     * @param _betNum The bet number, must be between 1 and 25.
     */
    function play(uint256 _lootboxId, uint256 _betNum) external {
        require(_betNum < 26, "Not correct bet");
        require(_betNum > 0, "Not correct bet");
        require(
            getLootboxMaxPrize(_lootboxId) <= betCoin.balanceOf(address(this)),
            "Not enough balance in lootbox"
        );
        (bool isWin, , , ) = checkWin(msg.sender);
        require(!isWin, "Please get your win first");
        Lootbox memory loot = lootboxes[_lootboxId];
        require(loot.finishTs > block.timestamp, "Lootbox is closed");
        betCoin.transferFrom(msg.sender, address(this), loot.priceForPlay);
        BetDetail storage bet = betDetails[msg.sender];
        bet.betNum = _betNum;
        bet.lootboxId = _lootboxId;
        bet.randomNumRequestId = vrfV2Consumer.requestRandomWords();
        emit Play(msg.sender, block.timestamp, loot.priceForPlay, _lootboxId);
    }

    /**
     * @dev Claims the prize for the player
     * @param _selectedNft Boolean indicating whether the player selected an NFT prize
     */
    function getPrize(bool _selectedNft) external {
        address user = msg.sender;
        (
            bool isWin,
            bool isNft,
            uint256 winIndex,
            uint256 lootboxId
        ) = checkWin(user);
        require(isWin, "You don't win");
        Lootbox memory loot = lootboxes[lootboxId];
        if (isNft) {
            NFT memory _nft = loot.nftTokens[winIndex];
            if (_selectedNft) {
                ERC721 token = ERC721(_nft.contractAddress);
                if (token.ownerOf(_nft.tokenId) == address(this)) {
                    token.transferFrom(address(this), user, _nft.tokenId);
                    emit TakedNft(
                        user,
                        _nft.contractAddress,
                        _nft.tokenId,
                        lootboxId,
                        block.timestamp,
                        _nft.tokenPrice
                    );
                } else {
                    betCoin.transfer(user, _nft.tokenPrice);
                    emit TakedUsd(
                        user,
                        _nft.tokenPrice,
                        block.timestamp,
                        lootboxId
                    );
                }
            } else {
                betCoin.transfer(user, _nft.tokenPrice);
                emit TakedUsd(
                    user,
                    _nft.tokenPrice,
                    block.timestamp,
                    lootboxId
                );
            }
        } else {
            betCoin.transfer(
                user,
                loot.usdPrizes[winIndex - loot.nftTokens.length]
            );
            emit TakedUsd(
                user,
                loot.usdPrizes[winIndex - loot.nftTokens.length],
                block.timestamp,
                lootboxId
            );
        }
        delete betDetails[user];
    }

    /**
     * @dev Withdraws ERC20 tokens from the contract
     * @param _tokenAddress The address of the ERC20 token
     * @param _amount The amount of tokens to withdraw
     */
    function withdrawERC20(
        address _tokenAddress,
        uint256 _amount
    ) external onlyOwner {
        ERC20 token = ERC20(_tokenAddress);
        require(
            _amount <= token.balanceOf(address(this)),
            "Not enough balance"
        );
        token.transfer(msg.sender, _amount);
    }

    /**
     * @dev Withdraws ERC721 tokens from the contract
     * @param _tokenAddress The address of the ERC721 token
     * @param _tokenId The ID of the ERC721 token to withdraw
     * @param _lootboxId The ID of the lootbox associated with the token
     */
    function withdrawERC721(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _lootboxId
    ) external onlyOwner {
        require(
            checkLootboxId(_tokenAddress, _tokenId, _lootboxId),
            "Incorrect lootbox"
        );
        require(
            lootboxes[_lootboxId].finishTs < block.timestamp,
            "lootbox are not closed"
        );
        ERC721 token = ERC721(_tokenAddress);
        require(token.ownerOf(_tokenId) == (address(this)), "Invalid token owner");
        token.transferFrom(address(this), msg.sender, _tokenId);
        emit TakedNft(
            msg.sender,
            _tokenAddress,
            _tokenId,
            _lootboxId,
            block.timestamp,
            0
        );
    }

    /**
     * @dev Returns the remaining time in seconds until a lootbox finishes
     * @param _lootboxId The ID of the lootbox
     * @return _remainingTS The remaining time in seconds
     */
    function getLootboxRemainingTS(
        uint256 _lootboxId
    ) external view returns (uint256 _remainingTS) {
        if (lootboxes[_lootboxId].finishTs <= block.timestamp) {
            return 0;
        } else {
            return lootboxes[_lootboxId].finishTs - block.timestamp;
        }
    }

    /**
     * @dev Returns the NFTs, USD prizes, and probabilities of a lootbox
     * @param _lootboxId The ID of the lootbox
     * @return _nfts The array of NFTs in the lootbox
     * @return _usdPrizes The array of USD prizes in the lootbox
     * @return _probabilities The array of probabilities corresponding to the prizes
     */
    function getLootboxPrizesAndProbabilities(
        uint256 _lootboxId
    )
        external
        view
        returns (
            NFT[] memory _nfts,
            uint256[] memory _usdPrizes,
            uint256[] memory _probabilities
        )
    {
        Lootbox memory loot = lootboxes[_lootboxId];
        _nfts = loot.nftTokens;
        _usdPrizes = loot.usdPrizes;
        _probabilities = loot.probabilities;
    }

    /**
     * @dev Returns the random number generated by VRF for a given request ID
     * @param _randomNumRequestId The request ID for the random number
     * @return The generated random number
     */
    function getRandomNumVRF(
        uint256 _randomNumRequestId
    ) public view returns (uint256) {
        (bool fulfilled, uint256 randNum) = vrfV2Consumer.getRequestStatus(
            _randomNumRequestId
        );
        require(fulfilled, "Not fulfilled");
        return randNum;
    }

    /**
     * @dev Checks if a player has won in a bet and provides additional details
     * @param player The address of the player
     * @return isWin True if the player has won, false otherwise
     * @return isNft True if the player has won an NFT prize, false otherwise
     * @return winIndex The index of the winning prize
     * @return lootboxId The ID of the lootbox associated with the bet
     */
    function checkWin(
        address player
    )
        public
        view
        returns (bool isWin, bool isNft, uint256 winIndex, uint256 lootboxId)
    {
        BetDetail memory bet = betDetails[player];
        lootboxId = bet.lootboxId;

        // If the player hasn't made a bet, return false and the lootbox ID
        if (bet.randomNumRequestId == 0) {
            return (false, false, 0, lootboxId);
        }

        uint256 randomNumber = getRandomNumVRF(bet.randomNumRequestId);
        Lootbox memory loot = lootboxes[bet.lootboxId];
        uint256 prizesCount = loot.nftTokens.length + loot.usdPrizes.length;

        // Generate a random number based on the player's bet
        randomNumber += bet.betNum;

        // Modulo operation to ensure the number is within the range of 0 to 99,999 (inclusive),
        // corresponding to the entire probability range from 0.001% to 100%.
        // This allows for a fair distribution of random numbers across the entire probability spectrum.
        randomNumber %= 100000;

        // Get the index of the prize won by the player
        winIndex = getPrizeIndex(lootboxId, randomNumber);

        // Check if the player has won a prize
        if (winIndex < prizesCount) {
            isWin = true;
            if (winIndex < loot.nftTokens.length) {
                isNft = true;
            }
        }
    }

    /**
     * @dev Calculates the index of the prize based on the generated random number and the probabilities
     * @param _lootboxId The ID of the lootbox
     * @param _randomNumber The generated random number
     * @return The index of the prize
     */
    function getPrizeIndex(
        uint256 _lootboxId,
        uint256 _randomNumber
    ) public view returns (uint256) {
        uint256[] memory _probabilities = lootboxes[_lootboxId].probabilities;
        uint256 sum;

        // Calculate the cumulative sum of probabilities and find the winning prize
        for (uint256 i; i < _probabilities.length; i++) {
            sum += _probabilities[i];
            if (_randomNumber <= sum) {
                return i;
            }
        }

        // If no prize is won, return a default value (100001)
        return 100001;
    }

    /**
     * @dev Returns the maximum prize amount among NFTs and USD prizes in a lootbox
     * @param _lootboxId The ID of the lootbox
     * @return The maximum prize amount
     */
    function getLootboxMaxPrize(
        uint256 _lootboxId
    ) public view returns (uint256) {
        Lootbox memory loot = lootboxes[_lootboxId];
        uint256 maxPrize;
        for (uint256 i; i < loot.nftTokens.length; i++) {
            if (loot.nftTokens[i].tokenPrice > maxPrize) {
                maxPrize = loot.nftTokens[i].tokenPrice;
            }
        }
        for (uint256 i; i < loot.usdPrizes.length; i++) {
            if (loot.usdPrizes[i] > maxPrize) {
                maxPrize = loot.usdPrizes[i];
            }
        }
        return maxPrize;
    }

    /**
     * @dev Checks if a given NFT is included in a specific lootbox
     * @param _tokenAddress The address of the NFT contract
     * @param _tokenId The ID of the NFT
     * @param _lootboxId The ID of the lootbox
     * @return True if the NFT is included in the lootbox, false otherwise
     */
    function checkLootboxId(
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _lootboxId
    ) public view returns (bool) {
        NFT[] memory _nfts = lootboxes[_lootboxId].nftTokens;
        for (uint256 i; i < _nfts.length; i++) {
            if (
                _nfts[i].contractAddress == _tokenAddress &&
                _nfts[i].tokenId == _tokenId
            ) {
                return true;
            }
        }
        return false;
    }
}

