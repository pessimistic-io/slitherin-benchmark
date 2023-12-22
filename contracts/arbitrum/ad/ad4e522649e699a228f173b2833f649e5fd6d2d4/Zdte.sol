// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ZdteLP} from "./ZdteLP.sol";

import {SafeERC20} from "./SafeERC20.sol";
import {Pausable} from "./Pausable.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {IERC721} from "./IERC721.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {Ownable} from "./Ownable.sol";

import {ZdtePositionMinter} from "./ZdtePositionMinter.sol";

import {ContractWhitelist} from "./ContractWhitelist.sol";

import {IOptionPricing} from "./IOptionPricing.sol";
import {IVolatilityOracle} from "./IVolatilityOracle.sol";
import {IPriceOracle} from "./IPriceOracle.sol";
import {IUniswapV3Router} from "./IUniswapV3Router.sol";

import "./console.sol";

contract Zdte is ReentrancyGuard, Ownable, Pausable, ContractWhitelist {
    using SafeERC20 for IERC20Metadata;

    // Base token
    IERC20Metadata public base;
    // Quote token
    IERC20Metadata public quote;
    // zdte Base LP token
    ZdteLP public baseLp;
    // zdte Quotee LP token
    ZdteLP public quoteLp;

    // Option pricing
    IOptionPricing public optionPricing;
    // Volatility oracle
    IVolatilityOracle public volatilityOracle;
    // Price oracle
    IPriceOracle public priceOracle;
    // zdte position minter
    ZdtePositionMinter public zdtePositionMinter;
    // Fee distributor
    address public feeDistributor;
    // Uniswap V3 router
    IUniswapV3Router public uniswapV3Router;

    // Fees for opening position
    uint256 public feeOpenPosition = 5000000; // 0.05%

    uint256 public constant STRIKE_DECIMALS = 1e8;

    uint256 internal constant AMOUNT_PRICE_TO_USDC_DECIMALS = (1e18 * 1e8) / 1e6;

    uint256 public MARGIN_DECIMALS = 100;

    uint256 public spreadMarginSafety = 300; // 300%

    uint256 internal constant AMOUNT_PRICE_TO_USD_DECIMALS = 1e20;

    // Strike increments
    uint256 public strikeIncrement;

    // Max OTM % from mark price
    uint256 public maxOtmPercentage;

    // Genesis expiry timestamp, next day 8am gmt
    uint256 public genesisExpiry;

    // base token liquidity
    uint256 public baseLpTokenLiquidty;

    // quote token liquidity
    uint256 public quoteLpTokenLiquidty;

    // oracle ID
    bytes32 public oracleId;

    // zdte positions
    mapping(uint256 => ZdtePosition) public zdtePositions;

    struct ZdtePosition {
        // Is position open
        bool isOpen;
        // Is short
        bool isPut;
        // Is spread
        bool isSpread;
        // Open position count (in base asset)
        uint256 positions;
        // Long strike price
        uint256 longStrike;
        // Short strike price
        uint256 shortStrike;
        // Long premium for position
        uint256 longPremium;
        // Short premium for position
        uint256 shortPremium;
        // Fees for position
        uint256 fees;
        // Final PNL of position
        int256 pnl;
        // Opened at timestamp
        uint256 openedAt;
        // Expiry timestamp
        uint256 expiry;
        // Margin
        uint256 margin;
    }

    // Deposit event
    event Deposit(bool isQuote, uint256 amount, address indexed sender);

    // Withdraw event
    event Withdraw(bool isQuote, uint256 amount, address indexed sender);

    // Long option position event
    event LongOptionPosition(uint256 id, uint256 amount, uint256 strike, address indexed user);

    // Spread option position event
    event SpreadOptionPosition(
        uint256 id, uint256 amount, uint256 longStrike, uint256 shortStrike, address indexed user
    );

    // Expire option position event
    event ExpireLongOptionPosition(uint256 id, uint256 pnl, address indexed user);

    // Expire spread position event
    event ExpireSpreadOptionPosition(uint256 id, uint256 pnl, address indexed user);

    constructor(
        address _base,
        address _quote,
        address _optionPricing,
        address _volatilityOracle,
        address _priceOracle,
        address _uniswapV3Router,
        uint256 _strikeIncrement,
        uint256 _maxOtmPercentage,
        uint256 _genesisExpiry
    ) {
        require(_base != address(0), "Invalid base token");
        require(_quote != address(0), "Invalid quote token");
        require(_optionPricing != address(0), "Invalid option pricing");
        require(_volatilityOracle != address(0), "Invalid volatility oracle");
        require(_priceOracle != address(0), "Invalid price oracle");

        require(_strikeIncrement > 0, "Invalid strike increment");
        require(_maxOtmPercentage > 0, "Invalid max OTM %");
        require(_genesisExpiry > block.timestamp, "Invalid genesis expiry");

        base = IERC20Metadata(_base);
        quote = IERC20Metadata(_quote);
        optionPricing = IOptionPricing(_optionPricing);
        volatilityOracle = IVolatilityOracle(_volatilityOracle);
        priceOracle = IPriceOracle(_priceOracle);
        uniswapV3Router = IUniswapV3Router(_uniswapV3Router);

        strikeIncrement = _strikeIncrement;
        maxOtmPercentage = _maxOtmPercentage;
        genesisExpiry = _genesisExpiry;

        zdtePositionMinter = new ZdtePositionMinter();

        base.approve(address(uniswapV3Router), type(uint256).max);
        quote.approve(address(uniswapV3Router), type(uint256).max);

        quoteLp = new ZdteLP(address(this), address(quote), quote.symbol());
        baseLp = new ZdteLP(address(this), address(base), base.symbol());

        quote.approve(address(quoteLp), type(uint256).max);
        base.approve(address(baseLp), type(uint256).max);
    }

    /// @notice Internal function to handle swaps using Uniswap V3 exactIn
    /// @param from Address of the token to sell
    /// @param to Address of the token to buy
    /// @param amountOut Target amount of to token we want to receive
    function _swapExactIn(address from, address to, uint256 amountIn) internal returns (uint256 amountOut) {
        return uniswapV3Router.exactInputSingle(
            IUniswapV3Router.ExactInputSingleParams({
                tokenIn: from,
                tokenOut: to,
                fee: 500,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    // Deposit assets
    // @param isQuote If true user deposits quote token (else base)
    // @param amount Amount of quote asset to deposit to LP
    function deposit(bool isQuote, uint256 amount) external whenNotPaused nonReentrant isEligibleSender {
        if (isQuote) {
            quoteLpTokenLiquidty += amount;
            quote.transferFrom(msg.sender, address(this), amount);
            quoteLp.deposit(amount, msg.sender);
        } else {
            baseLpTokenLiquidty += amount;
            base.transferFrom(msg.sender, address(this), amount);
            baseLp.deposit(amount, msg.sender);
        }
        emit Deposit(isQuote, amount, msg.sender);
    }

    // Withdraw
    // @param isQuote If true user withdraws quote token (else base)
    // @param amount Amount of LP positions to withdraw
    function withdraw(bool isQuote, uint256 amount) external whenNotPaused nonReentrant isEligibleSender {
        if (isQuote) {
            quoteLpTokenLiquidty -= amount;
            quoteLp.redeem(amount, msg.sender, msg.sender);
        } else {
            baseLpTokenLiquidty -= amount;
            baseLp.redeem(amount, msg.sender, msg.sender);
        }
        emit Withdraw(isQuote, amount, msg.sender);
    }

    /// @notice Buys a zdte option
    // @param isPut is put option
    // @param amount Amount of options to long // 1e18
    // @param strike Strike price // 1e8
    function longOptionPosition(bool isPut, uint256 amount, uint256 strike)
        external
        whenNotPaused
        nonReentrant
        isEligibleSender
        returns (uint256 id)
    {
        uint256 markPrice = getMarkPrice();
        require(
            (
                (isPut && ((strike >= ((markPrice * (100 - maxOtmPercentage)) / 100)) && strike <= markPrice))
                    || (!isPut && ((strike <= ((markPrice * (100 + maxOtmPercentage)) / 100)) && strike >= markPrice))
            ) && strike % strikeIncrement == 0,
            "Invalid strike"
        );

        // Calculate premium for option in quote (1e6)
        uint256 premium = calcPremium(isPut, strike, amount);

        // Calculate opening fees in quote (1e6)
        uint256 openingFees = calcFees((amount * strike) / AMOUNT_PRICE_TO_USD_DECIMALS);

        // We transfer premium + fees from user
        quote.transferFrom(msg.sender, address(this), premium + openingFees);

        if (isPut) {
            require(
                quoteLp.totalAvailableAssets() >= ((amount * strike) / AMOUNT_PRICE_TO_USD_DECIMALS),
                "Insufficient liquidity"
            );
            quoteLp.lockLiquidity((amount * strike) / AMOUNT_PRICE_TO_USD_DECIMALS);
        } else {
            require(baseLp.totalAvailableAssets() >= amount, "Insufficient liquidity");
            baseLp.lockLiquidity(amount);
        }

        // Transfer fees to fee distributor
        if (isPut) {
            quoteLp.deposit(openingFees, feeDistributor);
            quoteLp.addProceeds(premium);
        } else {
            uint256 basePremium = _swapExactIn(address(quote), address(base), premium);
            uint256 baseOpeningFees = _swapExactIn(address(quote), address(base), openingFees);
            baseLp.deposit(baseOpeningFees, feeDistributor);
            baseLp.addProceeds(basePremium);
        }

        // Generate zdte position NFT
        id = zdtePositionMinter.mint(msg.sender);

        zdtePositions[id] = ZdtePosition({
            isOpen: true,
            isPut: isPut,
            isSpread: false,
            positions: amount,
            longStrike: strike,
            shortStrike: 0,
            longPremium: premium,
            shortPremium: 0,
            fees: openingFees,
            pnl: 0,
            openedAt: block.timestamp,
            expiry: getCurrentExpiry(),
            margin: 0
        });

        emit LongOptionPosition(id, amount, strike, msg.sender);
    }

    /// @notice Sets up a zdte spread option position
    // @param isPut is put spread
    // @param amount Amount of options to long // 1e18
    // @param longStrike Long Strike price // 1e8
    // @param shortStrike Short Strike price // 1e8
    function spreadOptionPosition(bool isPut, uint256 amount, uint256 longStrike, uint256 shortStrike)
        external
        whenNotPaused
        nonReentrant
        isEligibleSender
        returns (uint256 id)
    {
        uint256 markPrice = getMarkPrice();
        require(
            (
                (
                    isPut && ((longStrike >= ((markPrice * (100 - maxOtmPercentage)) / 100)) && longStrike <= markPrice)
                        && longStrike > shortStrike
                )
                    || (
                        !isPut
                            && ((longStrike <= ((markPrice * (100 + maxOtmPercentage)) / 100)) && longStrike >= markPrice)
                            && longStrike < shortStrike
                    )
            ) && longStrike % strikeIncrement == 0,
            "Invalid long strike"
        );
        require(
            (
                (
                    isPut
                        && ((shortStrike >= ((markPrice * (100 - maxOtmPercentage)) / 100)) && shortStrike <= markPrice)
                        && shortStrike < longStrike
                )
                    || (
                        !isPut
                            && ((shortStrike <= ((markPrice * (100 + maxOtmPercentage)) / 100)) && shortStrike >= markPrice)
                            && shortStrike > longStrike
                    )
            ) && shortStrike % strikeIncrement == 0,
            "Invalid short strike"
        );

        // Calculate premium for long option in quote (1e6)
        uint256 longPremium = calcPremium(isPut, longStrike, amount);

        // Calculate premium for short option in quote (1e6)
        uint256 shortPremium = calcPremium(isPut, shortStrike, amount);

        uint256 premium = isPut ? longPremium - shortPremium : shortPremium - longPremium;
        require(premium > 0, "Premium must be greater than 0");

        // Calculate margin required for payouts
        uint256 margin = (calcMargin(isPut, longStrike, shortStrike) * amount) / 1 ether;

        // Calculate opening fees in quote (1e6)
        uint256 openingFees = calcFees((amount * (longStrike + shortStrike)) / AMOUNT_PRICE_TO_USD_DECIMALS);

        // We transfer premium + fees from user
        quote.transferFrom(msg.sender, address(this), premium + openingFees);

        if (isPut) {
            require(quoteLp.totalAvailableAssets() >= margin, "Insufficient liquidity");
            quoteLp.lockLiquidity(margin);
        } else {
            require(baseLp.totalAvailableAssets() >= margin, "Insufficient liquidity");
            baseLp.lockLiquidity(margin);
        }

        // Transfer fees to fee distributor
        if (isPut) {
            quoteLp.deposit(openingFees, feeDistributor);
            quoteLp.addProceeds(premium);
        } else {
            uint256 basePremium = _swapExactIn(address(quote), address(base), premium);
            uint256 baseOpeningFees = _swapExactIn(address(quote), address(base), openingFees);
            baseLp.deposit(baseOpeningFees, feeDistributor);
            baseLp.addProceeds(basePremium);
        }

        // Generate zdte position NFT
        id = zdtePositionMinter.mint(msg.sender);

        zdtePositions[id] = ZdtePosition({
            isOpen: true,
            isPut: isPut,
            isSpread: true,
            positions: amount,
            longStrike: longStrike,
            shortStrike: shortStrike,
            longPremium: longPremium,
            shortPremium: shortPremium,
            fees: openingFees,
            pnl: 0,
            openedAt: block.timestamp,
            expiry: getCurrentExpiry(),
            margin: margin
        });

        emit SpreadOptionPosition(id, amount, longStrike, shortStrike, msg.sender);
    }

    /// @notice Expires an open long option position
    /// @param id ID of position
    function expireLongOptionPosition(uint256 id) external whenNotPaused nonReentrant isEligibleSender {
        require(zdtePositions[id].isOpen, "Invalid position ID");
        require(!zdtePositions[id].isSpread, "Must be a long option position");

        require(zdtePositions[id].expiry <= block.timestamp, "Position must be past expiry time");

        uint256 pnl = calcPnl(id);

        if (pnl > 0) {
            if (zdtePositions[id].isPut) {
                quoteLp.unlockLiquidity(
                    (zdtePositions[id].longStrike * zdtePositions[id].positions) / AMOUNT_PRICE_TO_USD_DECIMALS
                );
                quoteLp.subtractLoss(pnl);
                quote.transfer(IERC721(zdtePositionMinter).ownerOf(id), pnl);
            } else {
                baseLp.unlockLiquidity(zdtePositions[id].positions);
                baseLp.subtractLoss(pnl);
                base.transfer(IERC721(zdtePositionMinter).ownerOf(id), pnl);
            }
        } else if (zdtePositions[id].isPut) {
            quoteLp.unlockLiquidity(
                (zdtePositions[id].longStrike * zdtePositions[id].positions) / AMOUNT_PRICE_TO_USD_DECIMALS
            );
        } else {
            baseLp.unlockLiquidity(zdtePositions[id].positions);
        }

        zdtePositions[id].isOpen = false;
        zdtePositionMinter.burn(id);

        emit ExpireLongOptionPosition(id, pnl, msg.sender);
    }

    /// @notice Expires an spread option position
    /// @param id ID of position
    function expireSpreadOptionPosition(uint256 id) external whenNotPaused nonReentrant isEligibleSender {
        require(zdtePositions[id].isOpen, "Invalid position ID");
        require(zdtePositions[id].isSpread, "Must be a spread option position");

        require(zdtePositions[id].expiry <= block.timestamp, "Position must be past expiry time");

        uint256 pnl = calcPnl(id);
        uint256 margin = zdtePositions[id].margin;

        if (pnl > 0) {
            if (zdtePositions[id].isPut) {
                quoteLp.unlockLiquidity(margin);
                quoteLp.subtractLoss(pnl);
                quote.transfer(IERC721(zdtePositionMinter).ownerOf(id), pnl);
            } else {
                baseLp.unlockLiquidity(margin);
                baseLp.subtractLoss(pnl);
                base.transfer(IERC721(zdtePositionMinter).ownerOf(id), pnl);
            }
        } else if (zdtePositions[id].isPut) {
            quoteLp.unlockLiquidity(margin);
        } else {
            baseLp.unlockLiquidity(margin);
        }

        zdtePositions[id].isOpen = false;
        emit ExpireSpreadOptionPosition(id, pnl, msg.sender);
    }

    /// @notice Allow only zdte LP contract to claim collateral
    /// @param amount Amount of quote/base assets to transfer
    function claimCollateral(uint256 amount) public {
        require(
            msg.sender == address(quoteLp) || msg.sender == address(baseLp),
            "Only zdte LP contract can claim collateral"
        );
        if (msg.sender == address(quoteLp)) {
            quote.transfer(msg.sender, amount);
        } else if (msg.sender == address(baseLp)) {
            base.transfer(msg.sender, amount);
        }
    }

    /// @notice External function to return the volatility
    /// @param strike Strike of option
    function getVolatility(bool isPut, uint256 strike) public view returns (uint256 volatility) {
        bytes32 _oracleId = isPut ? keccak256("ETH-USD-PUTS") : keccak256("ETH-USD-CALLS");
        volatility = uint256(volatilityOracle.getVolatility(_oracleId, getCurrentExpiry(), strike));
    }

    /// @notice External function to return the volatility
    /// @param strike Strike of option
    /// @param expiry Expiry of option
    function getVolatilityWithExpiry(bool isPut, uint256 strike, uint256 expiry) public view returns (uint256 volatility) {
        bytes32 _oracleId = isPut ? keccak256("ETH-USD-PUTS") : keccak256("ETH-USD-CALLS");
        volatility = uint256(volatilityOracle.getVolatility(_oracleId, expiry, strike));
    }

    /// @notice External function to validate spread position
    /// @param isPut is put spread
    /// @param amount Amount of options to long // 1e18
    /// @param longStrike Long Strike price // 1e8
    /// @param shortStrike Short Strike price // 1e8
    function canOpenSpreadPosition(bool isPut, uint256 amount, uint256 longStrike, uint256 shortStrike)
        external
        view
        returns (bool)
    {
        uint256 margin = (calcMargin(isPut, longStrike, shortStrike) * amount) / 1 ether;

        return isPut ? quoteLp.totalAvailableAssets() >= margin : baseLp.totalAvailableAssets() >= margin;
    }

    /// @notice Internal function to calculate premium in quote
    /// @param isPut if calc premium for put
    /// @param strike Strike of option
    /// @param amount Amount of option
    function calcPremium(
        bool isPut,
        uint256 strike, // 1e8
        uint256 amount
    ) public view returns (uint256 premium) {
        uint256 markPrice = getMarkPrice(); // 1e8
        premium = uint256(
            optionPricing.getOptionPrice(isPut, getCurrentExpiry(), strike, markPrice, getVolatility(isPut, strike))
        ) * amount; // ATM options: does not matter if call or put
        // Convert to 6 decimal places (quote asset)
        premium = premium / AMOUNT_PRICE_TO_USDC_DECIMALS;
    }

    /// @notice Internal function to calculate premium in quote
    /// @param strike Strike of option
    /// @param amount Amount of option
    function calcOpeningFees(
        uint256 strike, // 1e8
        uint256 amount // 1e18
    ) public view returns (uint256 premium) {
        return calcFees((amount * strike) / AMOUNT_PRICE_TO_USD_DECIMALS);
    }

    /// @notice Internal function to calculate margin for a spread option position
    /// @param id ID of position
    function calcMargin(uint256 id) internal view returns (uint256 margin) {
        ZdtePosition memory position = zdtePositions[id];
        margin = calcMargin(position.isPut, position.longStrike, position.shortStrike);
    }

    /// @notice Internal function to calculate margin for a spread option position
    /// @param isPut is put option
    /// @param longStrike Long strike price
    /// @param shortStrike Short strike price
    function calcMargin(bool isPut, uint256 longStrike, uint256 shortStrike) public view returns (uint256 margin) {
        margin = (isPut ? (longStrike - shortStrike) / 100 : ((shortStrike - longStrike) * 1 ether) / shortStrike);

        margin = (margin * spreadMarginSafety) / MARGIN_DECIMALS;
    }

    /// @notice Internal function to calculate fees
    /// @param amount Value of option in USD (ie6)
    function calcFees(uint256 amount) public view returns (uint256 fees) {
        fees = (amount * feeOpenPosition) / (100 * STRIKE_DECIMALS);
    }

    /// @notice Internal function to calculate pnl
    /// @param id ID of position
    /// @return pnl PNL in quote asset i.e USD (1e6)
    function calcPnl(uint256 id) public view returns (uint256 pnl) {
        uint256 markPrice = getMarkPrice();
        uint256 longStrike = zdtePositions[id].longStrike;
        uint256 shortStrike = zdtePositions[id].shortStrike;
        if (zdtePositions[id].isSpread) {
            if (zdtePositions[id].isPut) {
                pnl = longStrike > markPrice ? ((zdtePositions[id].positions) * (longStrike - markPrice)) / 10 ** 20 : 0;
                pnl -=
                    shortStrike > markPrice ? ((zdtePositions[id].positions) * (shortStrike - markPrice)) / 10 ** 20 : 0;
            } else {
                pnl = markPrice > longStrike
                    ? ((zdtePositions[id].positions * (markPrice - longStrike)) / markPrice / 1 ether)
                    : 0;
                pnl -= markPrice > shortStrike
                    ? ((zdtePositions[id].positions * (markPrice - shortStrike)) / markPrice / 1 ether)
                    : 0;
            }
        } else {
            if (zdtePositions[id].isPut) {
                pnl = longStrike > markPrice ? ((zdtePositions[id].positions) * (longStrike - markPrice)) / 10 ** 20 : 0;
            } else {
                pnl = markPrice > longStrike
                    ? ((zdtePositions[id].positions * (markPrice - longStrike)) / markPrice / 1 ether)
                    : 0;
            }
        }
    }

    /// @notice Public function to retrieve price of base asset from oracle
    /// @param price Mark price
    function getMarkPrice() public view returns (uint256 price) {
        price = uint256(priceOracle.getUnderlyingPrice());
    }

    /// @notice Public function to return the next expiry timestamp
    function getCurrentExpiry() public view returns (uint256 expiry) {
        if (block.timestamp > genesisExpiry) {
            expiry = genesisExpiry + ((((block.timestamp - genesisExpiry) / 1 days) + 1) * 1 days);
        } else {
            expiry = genesisExpiry;
        }
    }

    /// @notice update margin of safety
    /// @param _spreadMarginSafety New margin of safety
    function updateMarginOfSafety(uint256 _spreadMarginSafety) external onlyOwner {
        spreadMarginSafety = _spreadMarginSafety;
    }

    /// @notice update oracleId
    /// @param _oracleId Oracle Id
    function updateOracleId(bytes32 _oracleId) external onlyOwner {
        oracleId = _oracleId;
    }

    /// @notice Pauses the vault for emergency cases
    /// @dev Can only be called by admin
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the vault
    /// @dev Can only be called by admin
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Add a contract to the whitelist
    /// @dev Can only be called by the owner
    /// @param _contract Address of the contract that needs to be added to the whitelist
    function addToContractWhitelist(address _contract) external onlyOwner {
        _addToContractWhitelist(_contract);
    }

    /// @notice Remove a contract to the whitelist
    /// @dev Can only be called by the owner
    /// @param _contract Address of the contract that needs to be removed from the whitelist
    function removeFromContractWhitelist(address _contract) external onlyOwner {
        _removeFromContractWhitelist(_contract);
    }

    /// @notice Transfers all funds to msg.sender
    /// @dev Can only be called by admin
    /// @param tokens The list of erc20 tokens to withdraw
    /// @param transferNative Whether should transfer the native currency
    function emergencyWithdraw(address[] calldata tokens, bool transferNative) external onlyOwner whenPaused {
        if (transferNative) {
            payable(msg.sender).transfer(address(this).balance);
        }

        for (uint256 i; i < tokens.length;) {
            IERC20Metadata token = IERC20Metadata(tokens[i]);
            token.transfer(msg.sender, token.balanceOf(address(this)));

            unchecked {
                ++i;
            }
        }
    }
}

