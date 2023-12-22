//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";

import "./InterfaceArbiDogsNft.sol";
import "./InterfaceArbiDogsMinter.sol";

contract ArbiDogsMinter is InterfaceArbiDogsMinter, Ownable, ReentrancyGuard {
    uint256 public maxMintableTokens;

    InterfaceArbiDogsNft public arbiDogsNft;
    address public treasuryAddress;
    uint256 public fee;
    uint256 public tokenClaimed = 0;
    bool public isInitialized = false;
    bool public isWhitelistEnabled = true;
    mapping(address => bool) private whitelist;

    /**
     * @dev Allows only if NOT initialized
     */
    modifier onlyNotInitialized() {
        require(isInitialized == false, 'ArbiDogsMinter: contract already initialized');
        _;
    }

    /**
     * @dev Allows only if initialized
     */
    modifier onlyInitialized() {
        require(isInitialized, 'ArbiDogsMinter: contract not initialized');
        _;
    }

    /**
     * @dev initialize minter
     * @param _arbiDogsNft The address of ArbiDogsNft
     * @param _maxMintableTokens Max tokens to mint
     * @param _treasuryAddress Address where to transfer collected fees
     * @param _fee Fee for minting nft
     */
    function initialize(
        address _arbiDogsNft,
        uint256 _maxMintableTokens,
        address _treasuryAddress,
        uint256 _fee
    ) external onlyOwner onlyNotInitialized {
        require(_arbiDogsNft != address(0), 'ArbiDogsMinter: invalid ArbiDogsNft address');
        require(_maxMintableTokens > 0, 'ArbiDogsMinter: invalid _maxMintableTokens');

        arbiDogsNft = InterfaceArbiDogsNft(_arbiDogsNft);
        maxMintableTokens = _maxMintableTokens;
        _setTreasuryAddress(_treasuryAddress);
        _setFee(_fee);
        isInitialized = true;
        emit Initialize(_arbiDogsNft, _maxMintableTokens, _treasuryAddress, _fee);
    }

    /**
     * @dev Receive funds and call internal claim method
     */
    receive() external payable {
        _claim();
    }

    /**
     * @dev Claim tokenIds
     */
    function _claim() public payable onlyInitialized nonReentrant {
        if (isWhitelistEnabled) {
            require(whitelist[msg.sender], 'ArbiDogsMinter: User not on whitelist');
        }
        require(tokenClaimed < maxMintableTokens, 'ArbiDogsMinter: All tokens are sold');
        uint256 numberOfTokens = msg.value / fee;
        numberOfTokens = _Min(numberOfTokens, maxMintableTokens - tokenClaimed);
        require(numberOfTokens > 0, 'ArbiDogsMinter: Invalid number of tokens');

        uint256 totalPayValue = numberOfTokens * fee;

        for (uint256 i = 0; i < numberOfTokens; i++) {
            _mintToken(msg.sender);
        }

        (bool treasurySuccess, ) = treasuryAddress.call{value: totalPayValue}('');
        require(treasurySuccess, 'ArbiDogsMinter: Transfer to treasuryAddress failed');

        tokenClaimed = tokenClaimed + numberOfTokens;

        emit Claim(msg.sender, numberOfTokens);

        if (totalPayValue < msg.value) {
            (bool success, ) = msg.sender.call{value: msg.value - totalPayValue}('');
            require(success, 'ArbiDogsMinter: Transfer user surplus failed');
        }
    }

    /**
     * @dev _Min internal method to get min between two uint256
     * @param a who to compare
     * @param b compare with
     */
    function _Min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    /**
     * @dev _mintToken internal method to mint a token
     * @param user Receiver address of the minted token
     */
    function _mintToken(address user) internal {
        maxMintableTokens--;

        arbiDogsNft.mint(user);
    }

    /**
     * @dev Setter for fee
     */
    function setFee(uint256 _fee) external onlyOwner {
        _setFee(_fee);
        emit SetFee(_fee);
    }

    /**
     * @dev Add to whitelist
     */
    function addToWhitelist(address[] calldata toAddAddresses) external onlyOwner {
        for (uint256 i = 0; i < toAddAddresses.length; i++) {
            whitelist[toAddAddresses[i]] = true;
        }
        emit WhitelistUpdateAdd(toAddAddresses.length);
    }

    /**
     * @dev Remove from whitelist
     */
    function removeFromWhitelist(address[] calldata toRemoveAddresses) external onlyOwner {
        for (uint256 i = 0; i < toRemoveAddresses.length; i++) {
            delete whitelist[toRemoveAddresses[i]];
        }
        emit WhitelistUpdateRemove(toRemoveAddresses.length);
    }

    /**
     * @dev Enable whitelist
     */
    function enableWhitelist() external onlyOwner {
        isWhitelistEnabled = true;
        emit WhitelistEnabled();
    }

    /**
     * @dev Disable whitelist
     */
    function disableWhitelist() external onlyOwner {
        isWhitelistEnabled = false;
        emit WhitelistDisabled();
    }

    /**
     * @dev Increase max mintable tokens
     */
    function increaseMaxMintableTokens(uint256 amount) external onlyOwner {
        require(amount > 0, 'ArbiDogsMinter: invalid _maxMintableTokens');

        maxMintableTokens = maxMintableTokens + amount;

        emit MaxMintableTokensChanged(maxMintableTokens);
    }

    /**
     * @dev Increase max mintable tokens
     */
    function decreaseMaxMintableTokens(uint256 amount) external onlyOwner {
        require(amount > 0, 'ArbiDogsMinter: invalid _maxMintableTokens');
        require(
            amount <= maxMintableTokens,
            'ArbiDogsMinter: amount should not be greater than current maxMintableTokens'
        );

        maxMintableTokens = maxMintableTokens - amount;

        emit MaxMintableTokensChanged(maxMintableTokens);
    }

    /**
     * @dev Setter for treasury address
     */
    function setTreasuryAddress(address _treasuryAddress) external onlyOwner {
        _setTreasuryAddress(_treasuryAddress);
        emit SetTreasuryAddress(_treasuryAddress);
    }

    function _setFee(uint256 _fee) internal {
        require(_fee > 0, 'ArbiDogsMinter: invalid fee');
        fee = _fee;
    }

    function _setTreasuryAddress(address _treasuryAddress) internal {
        require(_treasuryAddress != address(0), 'ArbiDogsMinter: invalid treasury address');
        treasuryAddress = _treasuryAddress;
    }
}

