// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

import "./ERC20.sol";
import "./Ownable.sol";
import "./Camelotinterface.sol";
import "./TokenDividendTracker.sol";

/**
 * Moonbitrum token smart contract
 * @author Moonbitrum Team
 */

contract Moonbitrum is ERC20, Ownable {
    using SafeMath for uint256;

    //
    // State Variables
    //

    bool private swapping;
    bool public disableFees;
    TokenDividendTracker public dividendTracker;
    mapping(address => bool) private _isExcludedFromFee;

    // store addresses that are automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public automatedMarketMakerPairs;

    // Whitelisted Wallets are excluded from fees
    // Blacklisted wallets are excluded from tokrn transfers & swaps
    // Hindrance to hackers
    mapping(address => bool) public whiteList;
    mapping(address => bool) public blackList;

    ICamelotRouter public camelotRouter;
    address public camelotPair;

    address public constant USDTToken =
        0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9; // USDT Contract Address = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
    address public constant marketing =
        0x5cd2cBf12A1e492262C8816DE3eC96d1EAD2A252;
    address public constant teamwallet =
        0x3176De91dB0f69Ffe00E99ffC42913277BC0666a;
    address public constant treasuryWallet =
        0x3B2db4d00851bf070495cc257376BE5f76103B23;
    address public liquidityWallet;

    uint256 public maxSellTransactionAmount = 2500000 * 1e18; // 0.25% of total supply 1B
    uint256 public maxBuyTransactionAmount = 10000000 * 1e18; // 1% of total supply 21M

    uint256 private feeUnits = 1000;
    uint256 public standardFee = 40; // 4% buy fees
    uint256 public USDTRewardFee = 20; // 2% usdt rewards to holders
    uint256 public liquidityFee = 20; // 2% to liqudity

    uint256 public antiDumpFee = 20; // 2% extra for sell transactions
    uint256 public antiDumpBurn = 20; // extra 2% is burnt

    uint256 private liquidityBalance;
    uint256 public swapTokensAtAmount = 1000000 * (10 ** 18); // Contract accrues token which are swapped and distributed as rewards

    uint256 public gasForProcessing = 300000;

    uint256 public tradingEnabledTimestamp;
    bool public tradingEnabled = true;
    bool private initialized;

    //
    // Events:
    //

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    //
    // Constructor:
    //

    constructor() ERC20("MoonBitrum", "MBR") {
        dividendTracker = new TokenDividendTracker(
            "Moonbitrum_Dividend_Tracker",
            "Moonbitrum_Dividend_Tracker",
            USDTToken
        );

        // Deployer is liquidity provider
        liquidityWallet = owner();

        ICamelotRouter _camelotRouter = ICamelotRouter(
            0xc873fEcbd354f5A56E00E710B90EF4201db2448d // Camelot Router Contract  0xc873fEcbd354f5A56E00E710B90EF4201db2448d
        );
        camelotRouter = _camelotRouter;

        // Exclude from fees
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[liquidityWallet] = true;
        _isExcludedFromFee[marketing] = true;
        _isExcludedFromFee[teamwallet] = true;
        _isExcludedFromFee[treasuryWallet] = true;

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(liquidityWallet);
        dividendTracker.excludeFromDividends(teamwallet);
        dividendTracker.excludeFromDividends(address(_camelotRouter));

        _mint(owner(), 1000000000 * 1e18);
        tradingEnabledTimestamp = block.timestamp.add(2 days);
    }

    function initializePair() public onlyOwner {
        require(!initialized, "Already initialized");
        address factory = camelotRouter.factory();
        address _camelotPair = ICamelotFactory(factory).createPair(
            camelotRouter.WETH(),
            address(this)
        );
        camelotPair = _camelotPair;
        _setAutomatedMarketMakerPair(_camelotPair, true);
        initialized = true;
    }

    receive() external payable {}

    //
    // ADMIN CONTRACTS
    //

    /**
     * Function that allows only the owner to enable and disable trading
     * Can be used as a shield against attackers
     * Can be used during upgrades
     * @param _enabled boolean true or false
     */
    function setTradingEnabled(bool _enabled) external onlyOwner {
        tradingEnabled = _enabled;
    }

    function updateLiquidityWallet(
        address newLiquidityWallet
    ) external onlyOwner {
        require(
            newLiquidityWallet != liquidityWallet,
            "MoonBitrum: The liquidity wallet is already this address"
        );
        _isExcludedFromFee[newLiquidityWallet] = true;
        liquidityWallet = newLiquidityWallet;
    }

    /**
     * Function that allows only the owner to exclude an address from rewards
     */
    function excludeFromUsdtReward(address _address) external onlyOwner {
        dividendTracker.excludeFromDividends(_address);
    }

    /**
     * Function that allows only the owner to exclude an address from fees
     */
    function excludeFromFee(address _address) external onlyOwner {
        _isExcludedFromFee[_address] = true;
    }

    /**
     * Function that allows only the owner to include an address to fees
     */
    function includeToFee(address _address) external onlyOwner {
        _isExcludedFromFee[_address] = false;
    }

    /**
     * Function that allows only the owner set time to start trading
     */
    function setTradingEnabledTimestamp(uint256 timestamp) external onlyOwner {
        tradingEnabledTimestamp = timestamp;
    }

    /**
     * Function that allows only the owner to disable buy and sell fees
     */
    function updateDisableFees(bool _disableFees) external onlyOwner {
        if (_disableFees) {
            _removeDust();
        }
        disableFees = _disableFees;
    }

    /**
     * Function that allows only the owner to add an address to whitelist
     */
    function addToWhiteList(address _address) external onlyOwner {
        whiteList[_address] = true;
    }

    /**
     * Function that allows only the owner to exclude an address from whitelist
     */
    function execludeFromWhiteList(address _address) external onlyOwner {
        whiteList[_address] = false;
    }

    /**
     * Function that allows only the owner to add an address to blacklist
     */
    function addAddressToBlackList(address _address) external onlyOwner {
        blackList[_address] = true;
    }

    function setMultiToBlackList(
        address[] memory _addresses,
        bool _black
    ) external onlyOwner {
        for (uint i = 0; i < _addresses.length; i++) {
            blackList[_addresses[i]] = _black;
        }
    }

    /**
     * Function that allows only the owner to exclude an address from whitelist
     */
    function execludeAddressFromBlackList(address _address) external onlyOwner {
        blackList[_address] = false;
    }

    /**
     * Function that allows only the owner to change the number of accrued tokens to swap at
     */
    function updateSwapTokensAtAmount(uint256 _amount) external onlyOwner {
        swapTokensAtAmount = _amount;
    }

    function destroyTracker() external onlyOwner {
        disableFees = true;
        dividendTracker.destroyDividendTracker();
        _removeDust();
    }

    /**
     * Function that allows only the owner to remove tokens from the contract
     * Shield against attackers
     */
    function removeBadToken(IERC20 Token) external onlyOwner {
        require(
            address(Token) != address(this),
            "You cannot remove this Token"
        );
        Token.transfer(owner(), Token.balanceOf(address(this)));
    }

    /**
     * Function that allows only the owner to remove MBR tokens, ETH and USDT from the contract
     */
    function _removeDust() private {
        IERC20(USDTToken).transfer(
            owner(),
            IERC20(USDTToken).balanceOf(address(this))
        );
        IERC20(address(this)).transfer(
            owner(),
            IERC20(address(this)).balanceOf(address(this))
        );
        (bool success, ) = payable(owner()).call{value: address(this).balance}(
            ""
        );
        require(success, "Moonbitrum: ETH TRANSFER FAILED");
    }

    function setDividendTracker(
        TokenDividendTracker _dividendTracker
    ) external onlyOwner {
        dividendTracker = _dividendTracker;
        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(liquidityWallet);
        dividendTracker.excludeFromDividends(teamwallet);
        dividendTracker.excludeFromDividends(address(camelotRouter));
        _setAutomatedMarketMakerPair(camelotPair, true);
    }

    /**
     * Function that allows only the owner set gas for processing reward distribution
     */
    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(
            newValue >= 200000 && newValue <= 500000,
            "Moonbitrum: gasForProcessing must be between 200,000 and 500,000"
        );
        require(
            newValue != gasForProcessing,
            "Moonbitrum: Cannot update gasForProcessing to same value"
        );
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns (uint256) {
        return dividendTracker.claimWait();
    }

    /**
     * Function that allows only the owner update the max number of tokens to sell per transaction
     */
    function updateMaxSellAmount(uint256 _max) external onlyOwner {
        require(_max > 2500000 * 1e18 && _max < 10000000 * 1e18);
        maxSellTransactionAmount = _max;
    }

    /**
     * Function that allows only the owner update the max number of tokens to buy per transaction
     */
    function updateMaxBuyAmount(uint256 _max) external onlyOwner {
        require(_max > 5000000 * 1e18 && _max < 30000000 * 1e18);
        maxBuyTransactionAmount = _max;
    }

    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

    //
    // SWAP AND TRANSFER FUNCTIONS
    //

    /**
     * Function: Overrides ERC20 Transfer
     */
    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        return MbrTransfer(_msgSender(), to, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(sender, spender, amount);
        return MbrTransfer(sender, recipient, amount);
    }

    function MbrTransfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return true;
        }

        bool noFee = _isExcludedFromFee[from] ||
            _isExcludedFromFee[to] ||
            disableFees ||
            to == address(camelotRouter); // No fees when removing liquidity

        // Blacklisted can't transfer
        require(
            !(blackList[from] || blackList[to]),
            "Hacker Address Blacklisted"
        );

        if (
            !noFee &&
            (automatedMarketMakerPairs[from] ||
                automatedMarketMakerPairs[to]) &&
            !swapping
        ) {
            require(tradingEnabled, "Trading Disabled");
            require(
                block.timestamp >= tradingEnabledTimestamp ||
                    whiteList[from] ||
                    whiteList[to],
                "Trading Still Not Enabled"
            );

            uint256 contractBalance = balanceOf(address(this));
            if (contractBalance >= swapTokensAtAmount) {
                if (!swapping && !automatedMarketMakerPairs[from]) {
                    swapping = true;
                    swapAndLiquify();
                    swapAndSendDividends();
                    swapping = false;
                }
            }

            // Get buy fee amounts
            uint256 fees = amount.mul(standardFee).div(feeUnits);
            uint256 burnAmount;
            //            uint256 rewardAmount = amount.mul(USDTRewardFee).div(feeUnits);
            uint256 liquidityAmount = amount.mul(liquidityFee).div(feeUnits);

            if (automatedMarketMakerPairs[from]) {
                require(
                    amount <= maxBuyTransactionAmount,
                    "Max Buy Amount Error"
                );
            }

            // Selling: Get dump fee amounts
            if (automatedMarketMakerPairs[to]) {
                require(
                    amount <= maxSellTransactionAmount,
                    "Max Sell Amount Error"
                );
                fees = fees.add(amount.mul(antiDumpFee).div(feeUnits));
                burnAmount = burnAmount.add(
                    amount.mul(antiDumpBurn).div(feeUnits)
                );
            }
            if (burnAmount > 0) {
                _burn(from, burnAmount);
                super._transfer(from, address(this), fees.sub(burnAmount));
            }
            
            liquidityBalance = liquidityBalance.add(liquidityAmount);
            super._transfer(from, to, amount.sub(fees));
        } else {
            super._transfer(from, to, amount);
        }

        if (!disableFees) {
            dividendTracker.setBalance(from, balanceOf(from));
            dividendTracker.setBalance(to, balanceOf(to));

            if (!swapping && !noFee) {
                uint256 gas = gasForProcessing;
                try dividendTracker.process(gas) returns (
                    uint256 iterations,
                    uint256 claims,
                    uint256 lastProcessedIndex
                ) {
                    emit ProcessedDividendTracker(
                        iterations,
                        claims,
                        lastProcessedIndex,
                        true,
                        gas,
                        tx.origin
                    );
                } catch {}
            }
        }
        return true;
    }

    function swapAndLiquify() private {
        // split the contract balance into halves

        uint256 half = liquidityBalance.div(2);
        uint256 otherHalf = liquidityBalance.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half);
        // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        liquidityBalance = 0;

        // add liquidity to camelot
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the camelot pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = camelotRouter.WETH();

        _approve(address(this), address(camelotRouter), tokenAmount);

        // make the swap
        camelotRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            address(0),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(camelotRouter), tokenAmount);
        // add the liquidity
        camelotRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityWallet,
            block.timestamp
        );
    }

    function swapAndSendDividends() private {
        swapTokensForUsdt(balanceOf(address(this)), address(this));
        if (address(this).balance > 1e18) {
            // > 1ETH
            swapETHForUsdt();
        }
        uint256 dividends = IERC20(USDTToken).balanceOf(address(this));
        bool success = IERC20(USDTToken).transfer(
            address(dividendTracker),
            dividends
        );
        if (success) {
            dividendTracker.distributeUSDTDividends(dividends);
        }
    }

    function swapETHForUsdt() private {
        address[] memory path = new address[](2);
        path[0] = camelotRouter.WETH();
        path[1] = USDTToken;
        // make the swap
        camelotRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: address(this).balance
        }(0, path, address(this), address(0), block.timestamp);
    }

    function swapTokensForUsdt(uint256 tokenAmount, address recipient) private {
        // generate the camelot pair path of weth -> Usdt
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = camelotRouter.WETH();
        path[2] = USDTToken;

        _approve(address(this), address(camelotRouter), tokenAmount);

        // make the swap
        camelotRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of USDT
            path,
            recipient,
            address(0),
            block.timestamp
        );
    }

    function setAutomatedMarketMakerPair(
        address pair,
        bool value
    ) external onlyOwner {
        require(
            pair != camelotPair,
            "MoonBitrum: The camelot pair cannot be removed from automatedMarketMakerPairs"
        );
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "MoonBitrum: Automated market maker pair is already set to that value"
        );
        automatedMarketMakerPairs[pair] = value;

        if (value) {
            try dividendTracker.excludeFromDividends(pair) {} catch {
                // already excluded
            }
        }
        emit SetAutomatedMarketMakerPair(pair, value);
    }
}

