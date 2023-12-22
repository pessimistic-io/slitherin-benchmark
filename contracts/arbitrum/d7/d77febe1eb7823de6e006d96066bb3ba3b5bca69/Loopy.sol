// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.17;

// importing dependencies and required interfaces
import "./ReentrancyGuard.sol";
import "./Ownable2Step.sol";
import "./SafeERC20.sol";
import "./IFlashLoanRecipient.sol";
import "./LoopyConstants.sol";
import "./Swap.sol";

/**
 * @title Loopy
 * @notice This contract allows users to leverage their positions by borrowing 
 * assets, increasing their supply and thus enabling higher yields.
 * @dev The contract implements the ILoopy, LoopyConstantsMock, Swap, Ownable2Step, 
 * IFlashLoanRecipient, and ReentrancyGuard interfaces. It uses SafeERC20 for 
 * safe token transfers.
 */
contract Loopy is ILoopy, LoopyConstants, Swap, Ownable2Step, IFlashLoanRecipient, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // add mapping of token addresses to their decimal places
    mapping(IERC20 => uint8) public decimals;
    // add mapping to store the allowed tokens. Mapping provides faster access than array
    mapping(IERC20 => bool) public allowedTokens;
    // add mapping to store lToken contracts
    mapping(IERC20 => ICERC20) private lTokenMapping;
    // add mapping to store lToken collateral factors
    mapping(IERC20 => uint64) private collateralFactor;

    constructor() {
        // initialize decimals for each token
        decimals[USDC_NATIVE] = 6;
        decimals[USDC_BRIDGED] = 6;
        decimals[USDT] = 6;
        decimals[WBTC] = 8;
        decimals[DAI] = 18;
        decimals[FRAX] = 18;
        decimals[ARB] = 18;
        decimals[PLVGLP] = 18;

        // set the allowed tokens in the constructor
        // we can add/remove these with owner functions later
        allowedTokens[USDC_NATIVE] = true;
        allowedTokens[USDC_BRIDGED] = true;
        allowedTokens[USDT] = true;
        allowedTokens[WBTC] = true;
        allowedTokens[DAI] = true;
        allowedTokens[FRAX] = true;
        allowedTokens[ARB] = true;
        allowedTokens[PLVGLP] = true;

        // map tokens to lTokens
        lTokenMapping[USDC_NATIVE] = lUSDC;
        lTokenMapping[USDC_BRIDGED] = lUSDCe;
        lTokenMapping[USDT] = lUSDT;
        lTokenMapping[WBTC] = lWBTC;
        lTokenMapping[DAI] = lDAI;
        lTokenMapping[FRAX] = lFRAX;
        lTokenMapping[ARB] = lARB;
        lTokenMapping[PLVGLP] = lPLVGLP;

        // map lTokens to collateralFactors
        collateralFactor[USDC_NATIVE] = 820000000000000000;
        collateralFactor[USDC_BRIDGED] = 820000000000000000;
        collateralFactor[USDT] = 700000000000000000;
        collateralFactor[WBTC] = 750000000000000000;
        collateralFactor[DAI] = 750000000000000000;
        collateralFactor[FRAX] = 750000000000000000;
        collateralFactor[ARB] = 700000000000000000;
        collateralFactor[PLVGLP] = 750000000000000000;

        // approve glp contracts to spend USDC for minting GLP
        USDC_BRIDGED.approve(address(REWARD_ROUTER_V2), type(uint256).max);
        USDC_BRIDGED.approve(address(GLP), type(uint256).max);
        USDC_BRIDGED.approve(address(GLP_MANAGER), type(uint256).max);
        // approve GlpDepositor to spend GLP for minting plvGLP
        sGLP.approve(address(GLP_DEPOSITOR), type(uint256).max);
        GLP.approve(address(GLP_DEPOSITOR), type(uint256).max);
        sGLP.approve(address(REWARD_ROUTER_V2), type(uint256).max);
        GLP.approve(address(REWARD_ROUTER_V2), type(uint256).max);
        // approve balancer vault
        USDC_BRIDGED.approve(address(VAULT), type(uint256).max);
        USDT.approve(address(VAULT), type(uint256).max);
        WBTC.approve(address(VAULT), type(uint256).max);
        DAI.approve(address(VAULT), type(uint256).max);
        FRAX.approve(address(VAULT), type(uint256).max);
        ARB.approve(address(VAULT), type(uint256).max);
        // approve lTokens to be minted using underlying
        USDC_NATIVE.approve(address(lUSDC), type(uint256).max);
        USDC_BRIDGED.approve(address(lUSDCe), type(uint256).max);
        PLVGLP.approve(address(lPLVGLP), type(uint256).max);
        USDT.approve(address(lUSDT), type(uint256).max);
        WBTC.approve(address(lWBTC), type(uint256).max);
        DAI.approve(address(lDAI), type(uint256).max);
        FRAX.approve(address(lFRAX), type(uint256).max);
        ARB.approve(address(lARB), type(uint256).max);
        // approve uni router for native and bridged USDC swap
        USDC_NATIVE.approve(address(UNI_ROUTER), type(uint256).max);
        USDC_BRIDGED.approve(address(UNI_ROUTER), type(uint256).max);
        // approve our address to send tokens back to the user (used in the USDC native workflow)
        USDC_BRIDGED.approve(address(this), type(uint256).max);
    }

    // declare events
    event ProtocolFeeUpdated(uint256 amount);
    event AmountAddedToReserves(uint256 amount);

    /**
     * @notice Allows the owner to add a token to the platform
     * @param tokenAddress The token's contract address
     * @param tokenDecimals The token's decimal places
     * @param lTokenAddress The associated lToken contract's address
     */
    function addToken(IERC20 tokenAddress, uint8 tokenDecimals, ICERC20 lTokenAddress, uint64 tokenCollateralFactor) external onlyOwner {
        require(!allowedTokens[tokenAddress], "token already allowed");
        allowedTokens[tokenAddress] = true;

        // create our IERC20 object and map it accordingly
        ICERC20 _lTokenSymbol = ICERC20(lTokenAddress);
        decimals[tokenAddress] = tokenDecimals;
        lTokenMapping[tokenAddress] = _lTokenSymbol;
        collateralFactor[tokenAddress] = tokenCollateralFactor;

        // approve balance vault and the lToken market to be able to spend the newly added underlying
        tokenAddress.approve(address(VAULT), type(uint256).max);
        tokenAddress.approve(address(_lTokenSymbol), type(uint256).max);
    }

    /**
     * @notice Allows the owner to remove a token from the platform
     * @param tokenAddress The token's contract address
     */
    function removeToken(IERC20 tokenAddress) external onlyOwner {
        require(allowedTokens[tokenAddress], "token not allowed");
        allowedTokens[tokenAddress] = false;

        // nullify, essentially, existing records
        delete decimals[tokenAddress];
        delete lTokenMapping[tokenAddress];
        delete collateralFactor[tokenAddress];
    }

    /**
     * @notice Allows the owner to update the protocol's fee percentage
     * @param _protocolFeePercentage The new protocol fee percentage
     */
    function updateProtocolFeePercentage(uint256 _protocolFeePercentage) external onlyOwner {
        protocolFeePercentage = _protocolFeePercentage;
        emit ProtocolFeeUpdated(protocolFeePercentage);
    }

    /**
     * @notice Simulates a loop operation and checks whether the user can perform it with their current balance
     * @param _token The underlying token that the user wants to leverage
     * @param _amount The amount of the token that the user wants to use
     * @param _leverage The desired leverage (between 2x - 3x)
     * @param _user The user's address
     * @return 0 if the operation can be performed, 1 otherwise
     */
    function mockLoop(IERC20 _token, uint256 _amount, uint16 _leverage, address _user) external view returns (uint256) {
        {
            uint256 hypotheticalSupply;
            uint256 decimalScale;
            uint256 decimalExp;
            uint256 tokenDecimals;
            uint256 price;

            (uint256 loanAmount, IERC20 tokenToBorrow) = getNotionalLoanAmountIn1e18(_token, _amount, _leverage);

            loanAmount = loanAmount * (10000 + protocolFeePercentage) / 10000;

            // mock a hypothetical borrow to see what state it puts the account in (before factoring in our new liquidity)
            (, uint256 hypotheticalLiquidity, uint256 hypotheticalShortfall) = UNITROLLER
                .getHypotheticalAccountLiquidity(_user, address(lTokenMapping[tokenToBorrow]), 0, loanAmount);

            // if the account is still healthy without factoring in our newly supplied balance, we know for a fact they can support this operation.
            // so let's just return now and not waste any more time
            if (hypotheticalLiquidity > 0) {
                return 0; // pass
            } else {
                // otherwise, lets do some maths
                // lets get our hypotheticalSupply and and see if it's greater than our hypotheticalShortfall. if it is, we know the account can support this operation
                if (_token == PLVGLP) {
                    uint256 plvGLPPriceInEth = PLVGLP_ORACLE.getPlvGLPPrice();
                    tokenDecimals = (10 ** (decimals[PLVGLP]));
                    hypotheticalSupply =
                        (plvGLPPriceInEth * (loanAmount * (collateralFactor[PLVGLP] / 1e18))) /
                        tokenDecimals;
                } else {
                    // tokenToBorrow == _token in every instance that doesn't involve plvGLP (which borrows USDC)
                    uint256 tokenPriceInEth = PRICE_ORACLE.getUnderlyingPrice(address(lTokenMapping[tokenToBorrow]));
                    decimalScale = 18 - decimals[tokenToBorrow];
                    decimalExp = (10 ** decimalScale);
                    price = tokenPriceInEth / decimalExp;
                    tokenDecimals = (10 ** (decimals[tokenToBorrow]));
                    hypotheticalSupply =
                        (price * (loanAmount * (collateralFactor[tokenToBorrow] / 1e18))) /
                        tokenDecimals;
                }

                if (hypotheticalSupply > hypotheticalShortfall) {
                    return 0; // pass
                } else {
                    return 1; // fail
                }
            }
        }
    }

    /**
     * @notice Allows users to loop to a desired leverage, within pre-set ranges
     * @param _token The underlying token that the user wants to leverage
     * @param _amount The amount of the token that the user wants to use
     * @param _leverage The desired leverage (between 2x - 3x)
     * @param _useWalletBalance Flag to indicate if user's wallet balance should be used (0 being false, 1 being true)
     */
    function loop(IERC20 _token, uint256 _amount, uint16 _leverage, uint16 _useWalletBalance) external {
        require(allowedTokens[_token], "token not allowed to loop");
        require(tx.origin == msg.sender, "not an EOA");
        require(_amount > 0, "amount must be greater than 0");
        require(
            _leverage >= DIVISOR && _leverage <= MAX_LEVERAGE,
            "invalid leverage, range must be between DIVISOR and MAX_LEVERAGE values"
        );

        // mock loop when the user wants to use their existing lodestar balance.
        // if it fails we know the account cannot loop in the current state they are in
        if (_useWalletBalance == 0 && _token != PLVGLP && _token != USDC_NATIVE) {
            uint256 shortfall = this.mockLoop(_token, _amount, _leverage, msg.sender);
            require(
                shortfall == 0,
                "Existing balance on Lodestar unable to support operation. Please consider increasing your supply balance first."
            );
        }

        if (_useWalletBalance == 0 && (_token == PLVGLP || _token == USDC_NATIVE)) {
            uint256 amountPlusSlippage = (_amount * 101) / 100;
            uint256 shortfall = this.mockLoop(_token, amountPlusSlippage, _leverage, msg.sender);
            require(
                shortfall == 0,
                "Existing balance on Lodestar unable to support operation. Please consider increasing your supply balance first."
            );
        }
        // if the user wants us to mint using their existing wallet balance (indiciated with 1), then do so.
        // otherwise, read their existing balance and flash loan to increase their position
        if (_useWalletBalance == 1) {
            // transfer tokens to this contract so we can mint in 1 go.
            _token.safeTransferFrom(msg.sender, address(this), _amount);
        }

        uint256 loanAmount;
        IERC20 tokenToBorrow;

        (loanAmount, tokenToBorrow) = getNotionalLoanAmountIn1e18(_token, _amount, _leverage);

        if (tokenToBorrow.balanceOf(address(BALANCER_VAULT)) < loanAmount)
            revert FAILED("balancer vault token balance < loan");

        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = tokenToBorrow;

        uint256[] memory loanAmounts = new uint256[](1);
        loanAmounts[0] = loanAmount;

        UserData memory userData = UserData({
            user: msg.sender,
            tokenAmount: _amount,
            borrowedToken: tokenToBorrow,
            borrowedAmount: loanAmount,
            tokenToLoop: _token
        });

        BALANCER_VAULT.flashLoan(IFlashLoanRecipient(this), tokens, loanAmounts, abi.encode(userData));
    }

    /**
     * @notice Callback function to be executed after the flash loan operation
     * @param tokens Array of token addresses involved in the loan
     * @param amounts Array of token amounts involved in the loan
     * @param feeAmounts Array of fee amounts for the loan
     * @param userData Data regarding the user of the loan
     */
    function receiveFlashLoan(
        IERC20[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external override nonReentrant {
        if (msg.sender != address(BALANCER_VAULT)) revert UNAUTHORIZED("balancer vault is not the sender");

        UserData memory data = abi.decode(userData, (UserData));

        // ensure the transaction is user originated
        if (tx.origin != data.user) revert UNAUTHORIZED("user did not originate transaction");

        // ensure we borrowed the proper amounts
        if (data.borrowedAmount != amounts[0] || data.borrowedToken != tokens[0])
            revert FAILED("borrowed amounts and/or borrowed tokens do not match initially set values");

        // account for some plvGLP specific logic
        if (data.tokenToLoop == PLVGLP) {
            uint256 nominalSlippage = 5e16; // 5% slippage tolerance
            uint256 glpPrice = getGLPPrice(); // returns in 1e18
            uint256 minumumExpectedUSDCSwapAmount = (data.borrowedAmount) * (1e18 - nominalSlippage);
            uint256 minimumExpectedGlpSwapAmount = (minumumExpectedUSDCSwapAmount / (glpPrice * 1e18 / 1e18)) / 1e24; // accounting for plvGLP being less than 1 at times

            // mint GLP. approval needed
            uint256 glpAmount = REWARD_ROUTER_V2.mintAndStakeGlp(
                address(data.borrowedToken), // the token to buy GLP with
                data.borrowedAmount, // the amount of token to use for the purchase
                0, // the minimum acceptable USD value of the GLP purchased
                minimumExpectedGlpSwapAmount // the minimum acceptible GLP amount
            );
            if (glpAmount == 0) revert FAILED("glp=0");
            if (glpAmount < minimumExpectedGlpSwapAmount)
                revert FAILED("glp amount returned less than minumum expected swap amount");

            // this contract always needs to be whitelisted for plvGLP mint
            // mint plvGLP. approval needed
            uint256 _oldPlvglpBal = PLVGLP.balanceOf(address(this));
            GLP_DEPOSITOR.deposit(glpAmount);

            // check new balances and confirm we properly minted
            uint256 _newPlvglpBal = PLVGLP.balanceOf(address(this));
            require(_newPlvglpBal > _oldPlvglpBal, "glp deposit failed, new balance < old balance");
        }

        uint256 baseBorrowAmount;
        uint256 finalBal;

        // mint our respective token by depositing it into Lodestar's respective lToken contract (approval needed)
        unchecked {
            // if we are in the native usdc loop flow, let's make sure we swap our borrowed bridged usdc from balancer for native usdc before minting
            if (data.tokenToLoop == USDC_NATIVE) {
                uint256 bridgedUSDCBalance = USDC_BRIDGED.balanceOf(address(this));
                // account for slippage on the swap back to bridged USDC
                uint256 minAmountOut = (bridgedUSDCBalance * 99 / 100);
                Swap.swapThroughUniswap(
                    address(USDC_BRIDGED),
                    address(USDC_NATIVE),
                    bridgedUSDCBalance,
                    minAmountOut
                );
            }
            lTokenMapping[data.tokenToLoop].mint(data.tokenToLoop.balanceOf(address(this)));
            lTokenMapping[data.tokenToLoop].transfer(
                data.user,
                lTokenMapping[data.tokenToLoop].balanceOf(address(this))
            );
            finalBal = lTokenMapping[data.tokenToLoop].balanceOf(address(this));

            // emit lTokenBalance(_finalBal);
            require(finalBal == 0, "lToken balance not 0 at the end of loop");
        }

        uint256 repayAmountFactoringInFeeAmount;
        uint256 repayAmountFactoringInFeeAndSlippage;
        uint256 repayAmountFactoringInBothFeeAmounts;

        // factor in any balancer fees into the overall loan amount we wish to borrow
        uint256 currentBalancerFeePercentage = BALANCER_PROTOCOL_FEES_COLLECTOR.getFlashLoanFeePercentage();
        uint256 currentBalancerFeeAmount = (data.borrowedAmount * currentBalancerFeePercentage) / 1e18;

        // if the loop token is plvGLP or native USDC, we need to borrow a little more to account for extra fees
        if (data.tokenToLoop == PLVGLP || data.tokenToLoop == USDC_NATIVE) {
            // add in the various fees (balancer and protocol)
            baseBorrowAmount = (data.borrowedAmount * 101) / 100;
            repayAmountFactoringInFeeAmount = data.borrowedAmount + currentBalancerFeeAmount;
            repayAmountFactoringInFeeAndSlippage = baseBorrowAmount + currentBalancerFeeAmount;
            repayAmountFactoringInBothFeeAmounts = repayAmountFactoringInFeeAndSlippage * (10000 + protocolFeePercentage) / 10000;
        } else {
            // add in the various fees (balancer and protocol)
            repayAmountFactoringInFeeAmount = data.borrowedAmount + currentBalancerFeeAmount;
            repayAmountFactoringInBothFeeAmounts = repayAmountFactoringInFeeAmount * (10000 + protocolFeePercentage) / 10000;
        }

        uint256 amountToAddToReserves;
        if (data.tokenToLoop == PLVGLP || data.tokenToLoop == USDC_NATIVE) {
            // plvGLP requires us to repay the loan with USDC
            lUSDC.borrowBehalf(repayAmountFactoringInBothFeeAmounts, data.user);

            // transfer native USDC back into the contract after borrowing bridged USDC
            USDC_NATIVE.safeTransferFrom(data.user, address(this), repayAmountFactoringInBothFeeAmounts);

            // take the protocol fee while we still have native USDC and deposit it into the lUSDC market reserves
            uint256 slippage = repayAmountFactoringInFeeAndSlippage - repayAmountFactoringInFeeAmount;

            amountToAddToReserves = repayAmountFactoringInBothFeeAmounts - repayAmountFactoringInFeeAmount - slippage;
            lTokenMapping[USDC_NATIVE]._addReserves(amountToAddToReserves);
            emit AmountAddedToReserves(amountToAddToReserves);

            // we need to swap our native USDC for bridged USDC to repay the loan
            uint256 nativeUSDCBalance = USDC_NATIVE.balanceOf(address(this));
            Swap.swapThroughUniswap(
                address(USDC_NATIVE),
                address(USDC_BRIDGED),
                nativeUSDCBalance,
                repayAmountFactoringInFeeAmount
            );

            // transfer bridged USDC back to the user so we can repay the loan
            USDC_BRIDGED.safeTransferFrom(address(this), data.user, USDC_BRIDGED.balanceOf(address(this)));

            // repay loan, where msg.sender = vault
            USDC_BRIDGED.safeTransferFrom(data.user, msg.sender, repayAmountFactoringInFeeAmount);
        } else {
            // call borrowBehalf to borrow tokens on behalf of user
            lTokenMapping[data.tokenToLoop].borrowBehalf(repayAmountFactoringInBothFeeAmounts, data.user);

            // take the protocol fee while we still have native USDC and deposit it into the lUSDC market reserves
            amountToAddToReserves = repayAmountFactoringInBothFeeAmounts - repayAmountFactoringInFeeAmount;

            // transfer the reserves owed back to the contract after borrowing on the users behalf and before repaying the loan
            data.tokenToLoop.safeTransferFrom(data.user, address(this), amountToAddToReserves);
            lTokenMapping[data.tokenToLoop]._addReserves(amountToAddToReserves);
            emit AmountAddedToReserves(amountToAddToReserves);

            // repay loan, where msg.sender = vault
            data.tokenToLoop.safeTransferFrom(data.user, msg.sender, repayAmountFactoringInFeeAmount);
        }
    }

    /**
     * @notice Retrieves the current price of GLP from our PLVGLP Price Oracle.
    */
    function getGLPPrice() internal view returns (uint256) {
        uint256 price = PLVGLP_ORACLE.getGLPPrice();
        require(price > 0, "invalid glp price returned");
        return price; // glp oracle returns price scaled to 18 decimals, no need to extend here
    }

    /**
     * @dev Calculates the notional loan amount in a specific token, taking into account the specified leverage.
     * The notional loan amount is a way of calculating a loan amount that represents the underlying value of the loan, 
     * considering the token and the leverage used.
     * @param _token The ERC20 token for which the notional loan amount is to be calculated.
     * @param _amount The quantity of the token.
     * @param _leverage The leverage factor to apply to the loan amount.
     * @return _loanAmount The calculated notional loan amount.
     * @return _tokenToBorrow The ERC20 token to be borrowed.
     *
     * This function checks for the token type and applies different logic based on the type:
     * 1. For PLVGLP, the token price in Ethereum (ETH) and the USDC price in ETH are used to compute the loan amount.
     * 2. For USDC_NATIVE, the function calculates the loan amount based on the given amount and the leverage.
     * 3. For any other tokens, the function assumes that the loan will be in the supplied token and uses the given amount and the leverage to calculate the loan amount.
     */
    function getNotionalLoanAmountIn1e18(
        IERC20 _token,
        uint256 _amount,
        uint16 _leverage
    ) private view returns (uint256, IERC20) {
        // declare consts
        IERC20 _tokenToBorrow;
        uint256 _loanAmount;

        if (_token == PLVGLP) {
            uint256 _tokenPriceInEth;
            uint256 _usdcPriceInEth;
            uint256 _computedAmount;

            // constant used for converting plvGLP to USDC
            uint256 PLVGLP_DIVISOR = 1e30;

            // plvGLP borrows USDC to loop
            _tokenToBorrow = USDC_BRIDGED;
            _tokenPriceInEth = PRICE_ORACLE.getUnderlyingPrice(address(lTokenMapping[_token]));
            _usdcPriceInEth = (PRICE_ORACLE.getUnderlyingPrice(address(lUSDC)) / 1e12);
            _computedAmount = (_amount * (_tokenPriceInEth * 1e18 / _usdcPriceInEth)) / PLVGLP_DIVISOR;

            _loanAmount = _getNotionalLoanAmountIn1e18(_computedAmount, _leverage);
        } else if (_token == USDC_NATIVE) {
            _tokenToBorrow = USDC_BRIDGED;
            _loanAmount = _getNotionalLoanAmountIn1e18(
                _amount, // we can just send over the exact amount
                _leverage
            );
        } else {
            // the rest of the contracts just borrow whatever token is supplied
            _tokenToBorrow = _token;
            _loanAmount = _getNotionalLoanAmountIn1e18(
                _amount, // we can just send over the exact amount
                _leverage
            );
        }

        return (_loanAmount, _tokenToBorrow);
    }

    /**
     * @dev Internal helper function that calculates the notional loan amount based on the token quantity and the leverage.
     * @param _notionalTokenAmountIn1e18 The quantity of the token, represented in a denomination of 1e18.
     * @param _leverage The leverage factor to apply to the loan amount.
     * @return The notional loan amount, computed by multiplying the notional token amount by the leverage factor (minus the divisor), then dividing by the divisor.
     * 
     * The `unchecked` block is used to ignore overflow errors. This is because the operation of multiplying the leverage and the notional token amount may cause an overflow. 
     * The function assumes that the inputs (_notionalTokenAmountIn1e18 and _leverage) have been validated beforehand.
     */
    function _getNotionalLoanAmountIn1e18(
        uint256 _notionalTokenAmountIn1e18,
        uint16 _leverage
    ) private pure returns (uint256) {
        unchecked {
            return ((_leverage - DIVISOR) * _notionalTokenAmountIn1e18) / DIVISOR;
        }
    }
}

