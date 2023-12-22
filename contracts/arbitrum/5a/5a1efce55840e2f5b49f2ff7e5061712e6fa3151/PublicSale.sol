// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./Ownable.sol";
import "./IERC20.sol";

/**
 * @dev Error messages for require statements
 */
error SaleIsPaused();
error SaleIsOngoing();
error SaleIsOver();
error AmountIsTooLow();

interface IPublicSale {
    event SaleStarted(uint40 saleStartEpoch);
    event SalePaused(uint40 salePauseEpoch);
    event SaleExtended(uint40 saleEndEpoch);
    event BuyOrder(address indexed buyer, uint256 amount, uint256 tokens);
    event FundsWithdrawn(address indexed owner, uint256 amount);
}

/**
 * @title PublicSale
 * @dev A smart contract for a token public sale.
 */
contract PublicSale is IPublicSale, Ownable {
    // TOKEN PRICE
    // Only accept USDC for payment
    IERC20 public usdcToken;
    // max token for public sale: 100mm
    uint256 public immutable tokensForSale = 100_000_000 * 1e18;
    // price per token is 0.025 USDC
    uint256 public immutable pricePerToken = 25 * 1e3;

    // PUBLIC SALE DURATION
    // April 24th, 2023 12:00:00 UTC
    uint40 public saleEndEpoch = 1682337600;
    bool public isPaused = true;

    // PUBLIC SALE STATE
    mapping(address => uint256) public tokenBalances;
    uint256 public totalTokensSold;

    /**
     * @dev Constructor that sets the initial contract parameters.
     * @param _usdcToken The address of the USDC token contract.
     * @param _owner The address of the owner.
     */
    constructor(address _usdcToken, address _owner) {
        usdcToken = IERC20(_usdcToken);
        transferOwnership(_owner);
    }

    /**
     * @dev Modifier that checks if the sale has started.
     */
    modifier isNotPaused() {
        if (isPaused) revert SaleIsPaused();
        _;
    }

    /**
     * @dev Modifier that checks if the sale is still ongoing.
     */
    modifier duringSale() {
        if (block.timestamp > saleEndEpoch) revert SaleIsOver();
        _;
    }

    /**
     * @dev Modifier that checks if the sale has ended.
     */
    modifier afterSale() {
        if (block.timestamp <= saleEndEpoch) revert SaleIsOngoing();
        _;
    }

    /**
     * @dev Function that allows users to preview the amount of tokens they will get.
     * @param _usdcAmount The amount of USDC to spend.
     */
    function previewBuyTokens(
        uint256 _usdcAmount
    ) public pure returns (uint256) {
        // example calculation: 1 * 1e6 USDC = 40 * 1e18 tokens
        return (_usdcAmount * 1e18) / pricePerToken;
    }

    /**
     * @dev Function that allows users to buy tokens.
     * @param _usdcAmount The amount of USDC to spend.
     */
    function buyTokens(uint256 _usdcAmount) external isNotPaused duringSale {
        uint256 tokenAmount = previewBuyTokens(_usdcAmount);
        require(
            totalTokensSold + tokenAmount <= tokensForSale,
            "Exceeds sale allocation"
        );
        if (tokenAmount <= 1) revert AmountIsTooLow();
        bool success = usdcToken.transferFrom(
            msg.sender,
            address(this),
            _usdcAmount
        );
        require(success, "Transfer failed");
        tokenBalances[msg.sender] += tokenAmount;
        totalTokensSold += tokenAmount;
        emit BuyOrder(msg.sender, _usdcAmount, tokenAmount);
    }

    /**
     * @dev Function that allows the owner to extend the sale duration by 7 days.
     */
    function extendSale() external onlyOwner duringSale {
        saleEndEpoch += 7 days;
        emit SaleExtended(saleEndEpoch);
    }

    /**
     * @dev Function that allows the owner to withdraw the USDC balance.
     */
    function withdrawUsdc() external onlyOwner afterSale {
        uint256 balance = usdcToken.balanceOf(address(this));
        bool success = usdcToken.transfer(owner(), balance);

        require(success, "Transfer failed");
        emit FundsWithdrawn(owner(), balance);
    }

    /**
     * @dev Function that allows the owner toggle pause state.
     */
    function togglePause() external onlyOwner {
        isPaused = !isPaused;
        if (isPaused) {
            emit SalePaused(uint40(block.timestamp));
        } else {
            emit SaleStarted(uint40(block.timestamp));
        }
    }
}

