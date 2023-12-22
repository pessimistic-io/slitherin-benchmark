// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import "./ERC20.sol";
import "./Ownable.sol";

/**
 * @title PrivateLBE
 * @dev The contract for the public liquidity bootstrapping event (LBE) of the Rosa Finance decentralized lending and borrowing dApp.
 */
contract PublicLBE is Ownable {
    ERC20 public token;
    ERC20 public usdc;
    address payable public rosaWallet;
    address payable public usdcWallet;
    uint256 public rate = 3;
    uint256 public openingTime;
    uint256 public closingTime;
    uint256 public totalSoldTokens;

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
     * @dev Initializes the PublicLBE contract.
     * @param _openingTime The opening time of the liquidity bootstrapping event.
     * @param _closingTime The closing time of the liquidity bootstrapping event.
     * @param _rosaWallet The address of the wallet that holds the ROSA tokens.
     * @param _usdcWallet The address of the wallet that receives USDC.
     * @param _token The ERC20 token contract representing ROSA.
     * @param _usdc The ERC20 token contract representing USDC.
     * @param _owner The address of the contract owner.
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
     * @dev Modifier to check if the liquidity bootstrapping event is still ongoing.
     *      Reverts if the event has ended.
     */
    modifier onlyWhileOpen {
        require(block.timestamp >= openingTime && block.timestamp <= closingTime, "Crowdsale is closed.");
        _;
    }

    /**
     * @dev Allows a user to buy tokens during the liquidity bootstrapping event.
     * @param _beneficiary The address of the beneficiary who will receive the tokens.
     * @param _usdcAmount The amount of USDC to be used for token purchase.
     */
    function buyTokens(address _beneficiary, uint256 _usdcAmount) external onlyWhileOpen {
        require(_usdcAmount > 0, "Amount should be greater than 0");

        uint256 tokens = _getTokenAmount(_usdcAmount);

        uint256 rosaWalletBalance = token.balanceOf(rosaWallet); // check balance of ROSA Wallet
        require(rosaWalletBalance >= tokens, "Not enough ROSA left for sale");

        require(usdc.transferFrom(msg.sender, usdcWallet, _usdcAmount), "Failed to transfer USDC from buyer");

        // Record the purchase info 
        purchases[_beneficiary] = PurchaseInfo({
            totalTokens: tokens,
            claimedTokens: 0,
            vestingStart: block.timestamp
        });

        totalSoldTokens += tokens;

        emit TokenPurchase(msg.sender, _beneficiary, _usdcAmount, tokens);
    }

    /**
     * @dev Converts the specified USDC amount to ROSA tokens based on the current rate.
     * @param usdcAmount The amount of USDC to be converted.
     * @return The equivalent amount of ROSA tokens.
     */
    function _getTokenAmount(uint256 usdcAmount) internal pure returns (uint256) {
        // Price of 1 ROSA in USDC is 3, with ROSA having 18 decimals and USDC 6 decimals
        return (usdcAmount * 10**12) / 3;
    }

    /**
     * @dev Checks if the liquidity bootstrapping event has closed.
     * @return A boolean indicating whether the event has closed.
     */
    function hasClosed() public view returns (bool) {
        return block.timestamp > closingTime;
    }

    /**
     * @dev Allows a user to claim their vested ROSA tokens.
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

        // Update claimed tokens
        purchase.claimedTokens = vestedTokens;

        require(token.transferFrom(rosaWallet, msg.sender, tokensToClaim), "Failed to transfer ROSA to buyer."); // transfer from ROSA Wallet

        emit TokenClaimed(msg.sender, tokensToClaim);
    }

    /**
     * @dev Gets the amount of ROSA tokens claimable by a user.
     * @param _user The address of the user.
     * @return The amount of ROSA tokens claimable by the user.
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

