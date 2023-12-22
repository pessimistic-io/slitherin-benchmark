// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import "./ERC20.sol";
import "./Ownable.sol";

/**
 * @title PrivateLBE
 * @dev The contract for the private liquidity bootstrapping event (LBE) of the Rosa Finance decentralized lending and borrowing dApp.
 */
contract PrivateLBE is Ownable {
    ERC20 public token;
    ERC20 public usdc;
    address payable public rosaWallet;
    address payable public usdcWallet;
    uint256 public rate = 3;
    uint256 public openingTime;
    uint256 public closingTime;
    uint256 public totalSoldTokens;
    mapping(address => bool) public whitelist;

    uint256 public constant VESTING_PERIOD = 7 days;

    struct PurchaseInfo {
        uint256 totalTokens;
        uint256 claimedTokens;
        uint256 vestingStart;
    }

    mapping(address => PurchaseInfo) public purchases;

    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    event TokenClaimed(address indexed purchaser, uint256 amount);

    /**
     * @dev Initializes the PrivateLBE contract.
     * @param _openingTime The opening time of the LBE event.
     * @param _closingTime The closing time of the LBE event.
     * @param _rosaWallet The address of the ROSA token wallet.
     * @param _usdcWallet The address of the USDC wallet.
     * @param _token The ERC20 token contract representing ROSA.
     * @param _usdc The ERC20 token contract representing USDC.
     * @param _owner The initial owner of the contract.
     */
    constructor(
        uint256 _openingTime,
        uint256 _closingTime,
        address payable _rosaWallet,
        address payable _usdcWallet,
        ERC20 _token,
        ERC20 _usdc,
        address _owner
    ) Ownable(_owner) {
        require(_openingTime >= block.timestamp);
        require(_closingTime >= _openingTime);
        require(_rosaWallet != address(0));
        require(_usdcWallet != address(0));
        require(address(_token) != address(0));
        require(address(_usdc) != address(0));

        openingTime = _openingTime;
        closingTime = _closingTime;
        rosaWallet = _rosaWallet;
        usdcWallet = _usdcWallet;
        token = _token;
        usdc = _usdc;
        totalSoldTokens = 0;
    }

    /**
     * @dev Modifier to check if an address is whitelisted.
     * @param _beneficiary The address to check.
     */
    modifier isWhitelisted(address _beneficiary) {
        require(whitelist[_beneficiary], "Beneficiary not whitelisted.");
        _;
    }

    /**
     * @dev Modifier to check if the LBE event is still open.
     */
    modifier onlyWhileOpen {
        require(block.timestamp >= openingTime && block.timestamp <= closingTime, "Crowdsale is closed.");
        _;
    }

    /**
     * @dev Adds an address to the whitelist.
     * @param _beneficiary The address to add to the whitelist.
     */
    function addToWhitelist(address _beneficiary) external onlyOwner {
        whitelist[_beneficiary] = true;
    }

    /**
     * @dev Adds multiple addresses to the whitelist.
     * @param _beneficiaries The addresses to add to the whitelist.
     */
    function addManyToWhitelist(address[] calldata _beneficiaries) external onlyOwner {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            whitelist[_beneficiaries[i]] = true;
        }
    }

    /**
     * @dev Removes an address from the whitelist.
     * @param _beneficiary The address to remove from the whitelist.
     */
    function removeFromWhitelist(address _beneficiary) external onlyOwner {
        whitelist[_beneficiary] = false;
    }

    /**
     * @dev Allows a whitelisted beneficiary to purchase tokens with USDC.
     * @param _beneficiary The address of the beneficiary.
     * @param _usdcAmount The amount of USDC to be used for the purchase.
     */
    function buyTokens(address _beneficiary, uint256 _usdcAmount) external isWhitelisted(_beneficiary) onlyWhileOpen {
        require(_usdcAmount > 0, "Amount should be greater than 0");

        uint256 tokens = _getTokenAmount(_usdcAmount);

        uint256 rosaWalletBalance = token.balanceOf(rosaWallet);
        require(rosaWalletBalance >= tokens, "Not enough ROSA left for sale");

        require(usdc.transferFrom(msg.sender, usdcWallet, _usdcAmount), "Failed to transfer USDC from buyer");

        purchases[_beneficiary] = PurchaseInfo({
            totalTokens: tokens,
            claimedTokens: 0,
            vestingStart: block.timestamp
        });

        totalSoldTokens += tokens;

        emit TokenPurchase(msg.sender, _beneficiary, _usdcAmount, tokens);
    }

    /**
     * @dev Converts an amount of USDC to ROSA tokens based on the set rate.
     * @param usdcAmount The amount of USDC to convert.
     * @return The corresponding amount of ROSA tokens.
     */
    function _getTokenAmount(uint256 usdcAmount) internal pure returns (uint256) {
        return (usdcAmount * 10**12) / 3;
    }

    /**
     * @dev Checks if the LBE event has closed.
     * @return A boolean indicating whether the event has closed.
     */
    function hasClosed() public view returns (bool) {
        return block.timestamp > closingTime;
    }

    /**
     * @dev Allows a purchaser to claim their vested ROSA tokens.
     */
    function claimTokens() external {
        PurchaseInfo storage purchase = purchases[msg.sender];
        require(purchase.vestingStart > 0, "No ROSA to claim.");

        uint256 elapsedTime = block.timestamp - purchase.vestingStart;
        uint256 vestedTokens;

        if (elapsedTime >= VESTING_PERIOD) {
            vestedTokens = purchase.totalTokens;
        } else {
            vestedTokens = (purchase.totalTokens * elapsedTime) / VESTING_PERIOD;
        }

        uint256 tokensToClaim = vestedTokens - purchase.claimedTokens;
        require(tokensToClaim > 0, "No ROSA to claim.");

        purchase.claimedTokens = vestedTokens;

        require(token.transferFrom(rosaWallet, msg.sender, tokensToClaim), "Failed to transfer ROSA to buyer.");

        emit TokenClaimed(msg.sender, tokensToClaim);
    }

    /**
     * @dev Gets the amount of ROSA tokens that a user can claim.
     * @param _user The address of the user.
     * @return The amount of claimable ROSA tokens.
     */
    function getClaimableTokens(address _user) external view returns (uint256) {
        PurchaseInfo storage purchase = purchases[_user];
        if (purchase.vestingStart == 0) {
            return 0;
        }

        uint256 elapsedTime = block.timestamp - purchase.vestingStart;
        uint256 vestedTokens;

        if (elapsedTime >= VESTING_PERIOD) {
            vestedTokens = purchase.totalTokens;
        } else {
            vestedTokens = (purchase.totalTokens * elapsedTime) / VESTING_PERIOD;
        }

        uint256 tokensToClaim = vestedTokens - purchase.claimedTokens;

        return tokensToClaim;
    }

    /**
     * @dev Gets the total tokens purchased by a specific user.
     * @param _user The address of the user.
     * @return The total tokens purchased.
     */
    function getTotalPurchasedTokens(address _user) external view returns (uint256) {
        return purchases[_user].totalTokens;
    }

    /**
     * @dev Gets the total amount of ROSA sold to all users.
     * @return The total amount of ROSA sold.
     */
    function getTotalSoldTokens() external view returns (uint256) {
        return totalSoldTokens;
    }
    
}

