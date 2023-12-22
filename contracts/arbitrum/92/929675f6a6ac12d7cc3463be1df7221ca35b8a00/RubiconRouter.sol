// SPDX-License-Identifier: MIT

/// @author rubicon.eth
/// @notice This contract is a router to interact with the low-level functions present in RubiconMarket and Pools
pragma solidity ^0.8.17;
pragma abicoder v2;

import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./CTokenInterfaces.sol";
import "./IBathToken.sol";
import "./IBathBuddy.sol";
import "./IWETH.sol";
import "./RubiconMarket.sol";

///@dev this contract is a high-level router that utilizes Rubicon smart contracts to provide
///@dev added convenience and functionality when interacting with the Rubicon protocol
contract RubiconRouter {
    // Libs
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Storage vars
    address public RubiconMarketAddress;
    address payable public wethAddress;
    bool public started;
    /// @dev track when users make offers with/for the native asset so we can permission the cancelling of those orders
    mapping(address => uint256[]) public userNativeAssetOrders;
    bool locked;

    /// event LogNote(string, uint256); /// TODO: this event is not used in the contract, remove?

    /// event LogSwap(
    ///     uint256 inputAmount,
    ///     address inputERC20,
    ///     uint256 hurdleBuyAmtMin,
    ///     address targetERC20,
    ///     bytes32 indexed pair,
    ///     uint256 realizedFill,
    ///     address recipient
    /// );

    // Events
    event emitSwap(
        address indexed recipient,
        address indexed inputERC20,
        address indexed targetERC20,
        bytes32 pair,
        uint256 inputAmount,
        uint256 realizedFill,
        uint256 hurdleBuyAmtMin
    );

    // Modifiers
    /// @dev beGoneReentrantScum
    modifier beGoneReentrantScum() {
        require(!locked);
        locked = true;
        _;
        locked = false;
    }

    //============================= RECEIVE ETH =============================

    receive() external payable {}

    fallback() external payable {}

    //============================= PROXY-INIT =============================

    function startErUp(
        address _theTrap,
        address payable _weth
    ) external beGoneReentrantScum {
        require(!started);
        RubiconMarketAddress = _theTrap;
        wethAddress = _weth;
        started = true;
    }

    //============================= VIEW =============================

    /// @notice iterate through all baseToken/tokens[i] offers of maker
    /// @param baseToken - token pa_amt of which was sent to the market
    /// @param tokens - all the quote tokens for baseToken
    /// @param maker - owner of the offers
    /// @return balanceInBook - total balance of the baseToken of the maker in the market
    /// @return balance - balance of the baseToken of the maker
    function getMakerBalance(
        IERC20 baseToken,
        IERC20[] calldata tokens,
        address maker
    ) public view returns (uint256 balanceInBook, uint256 balance) {
        // find all active offers
        for (uint256 i = 0; i < tokens.length; ++i) {
            balanceInBook += getMakerBalanceInPair(baseToken, tokens[i], maker);
        }
        balance = baseToken.balanceOf(maker);
    }

    /// @notice get total pay_amt of maker across all the offers in asset/quote pair
    function getMakerBalanceInPair(
        IERC20 asset,
        IERC20 quote,
        address maker
    ) public view returns (uint256 balance) {
        uint256[] memory offerIDs = getOfferIDsFromPair(asset, quote);
        RubiconMarket market = RubiconMarket(RubiconMarketAddress);

        for (uint256 i = 0; i < offerIDs.length; ++i) {
            (uint256 pay_amt, , , , , , address owner) = market.offers(
                offerIDs[i]
            );

            if (owner == maker) {
                balance += pay_amt;
            }
            // else go to the next offer
        }
    }

    /// @notice Get all the outstanding orders from both sides of the order book for a given pair
    /// @dev The asset/quote pair ordering will affect return values - asset should be the top of the pair: for example, (ETH, USDC, 10) will return (10 best ETH asks, 10 best USDC bids, 10)
    /// @param asset the IERC20 token that represents the ask/sell side of the order book
    /// @param quote the IERC20 token that represents the bid/buy side of the order book
    function getBookFromPair(
        IERC20 asset,
        IERC20 quote
    ) public view returns (uint256[3][] memory asks, uint256[3][] memory bids) {
        asks = getOffersFromPair(asset, quote);
        bids = getOffersFromPair(quote, asset);
    }

    /// @notice inspect one side of the order book
    function getOffersFromPair(
        IERC20 tokenIn,
        IERC20 tokenOut
    ) public view returns (uint256[3][] memory offers) {
        (uint256 size, uint256 bestOfferID) = getBookDepth(tokenIn, tokenOut);

        offers = new uint256[3][](size);
        RubiconMarket market = RubiconMarket(RubiconMarketAddress);

        uint256 lastOffer = bestOfferID;

        for (uint256 index = 0; index < size; index++) {
            if (lastOffer == 0) {
                break;
            }

            (uint256 pay_amt, , uint256 buy_amt, ) = market.getOffer(lastOffer);

            offers[index] = [pay_amt, buy_amt, lastOffer];
            // update lastOffer with next best offer
            lastOffer = RubiconMarket(RubiconMarketAddress).getWorseOffer(
                lastOffer
            );
        }
    }

    /// @notice returns all offer ids from tokenIn/tokenOut pair
    function getOfferIDsFromPair(
        IERC20 tokenIn,
        IERC20 tokenOut
    ) public view returns (uint256[] memory IDs) {
        (uint256 size, uint256 lastOffer) = getBookDepth(tokenIn, tokenOut);
        RubiconMarket market = RubiconMarket(RubiconMarketAddress);
        IDs = new uint256[](size);

        for (uint256 i = 0; i < size; ++i) {
            if (lastOffer == 0) {
                break;
            }

            IDs[i] = lastOffer;

            // update lastOffer with next best offer
            lastOffer = market.getWorseOffer(lastOffer);
        }
    }

    /// @notice get depth of the one side of the order-book
    function getBookDepth(
        IERC20 tokenIn,
        IERC20 tokenOut
    ) public view returns (uint256 depth, uint256 bestOfferID) {
        RubiconMarket market = RubiconMarket(RubiconMarketAddress);
        bestOfferID = market.getBestOffer(tokenIn, tokenOut);
        depth = market.getOfferCount(tokenIn, tokenOut);
    }

    /// @dev this function returns the best offer for a pair's id and info
    function getBestOfferAndInfo(
        address asset,
        address quote
    )
        public
        view
        returns (
            uint256, //id
            uint256,
            IERC20,
            uint256,
            IERC20
        )
    {
        address _market = RubiconMarketAddress;
        uint256 offer = RubiconMarket(_market).getBestOffer(
            IERC20(asset),
            IERC20(quote)
        );
        (
            uint256 pay_amt,
            IERC20 pay_gem,
            uint256 buy_amt,
            IERC20 buy_gem
        ) = RubiconMarket(_market).getOffer(offer);
        return (offer, pay_amt, pay_gem, buy_amt, buy_gem);
    }

    /// @dev this function takes the same parameters of swap and returns the expected amount
    function getExpectedSwapFill(
        uint256 pay_amt,
        uint256 buy_amt_min,
        address[] calldata route // First address is what is being payed, Last address is what is being bought
    ) public view returns (uint256 currentAmount) {
        address _market = RubiconMarketAddress;

        for (uint256 i = 0; i < route.length - 1; i++) {
            (address input, address output) = (route[i], route[i + 1]);
            uint256 _pay = i == 0 ? pay_amt : currentAmount;

            // fee here should be excluded
            uint256 wouldBeFillAmount = RubiconMarket(_market).getBuyAmount(
                IERC20(output),
                IERC20(input),
                _pay
            );
            currentAmount = wouldBeFillAmount;
        }
        require(currentAmount >= buy_amt_min, "didnt clear buy_amt_min");
    }

    /// @dev this function takes the same parameters of multiswap and returns the expected amount
    function getExpectedMultiswapFill(
        uint256[] memory pay_amts,
        uint256[] memory buy_amt_mins,
        address[][] memory routes
    ) public view returns (uint256 outputAmount) {
        address _market = RubiconMarketAddress;

        address input;
        address output;
        uint256 currentAmount;

        for (uint256 i = 0; i < routes.length; ++i) {
            // loopinloop
            for (uint256 n = 0; n < routes[i].length - 1; ++n) {
                (input, output) = (routes[i][n], routes[i][n + 1]);

                uint256 _pay = n == 0 ? pay_amts[i] : currentAmount;

                // fee here should be excluded
                uint256 wouldBeFillAmount = RubiconMarket(_market).getBuyAmount(
                    IERC20(output),
                    IERC20(input),
                    _pay
                );
                currentAmount = wouldBeFillAmount;
            }
            require(
                currentAmount >= buy_amt_mins[i],
                "didnt clear buy_amt_min"
            );
            outputAmount += currentAmount;
        }
    }

    /// @notice A function that returns the index of uid from array
    /// @dev uid must be in array for the purposes of this contract to enforce outstanding trades per strategist are tracked correctly
    /// @dev can be used to check if a value is in a given array, and at what index
    function getIndexFromElement(
        uint256 uid,
        uint256[] storage array
    ) internal view returns (uint256 _index) {
        bool assigned = false;
        for (uint256 index = 0; index < array.length; index++) {
            if (uid == array[index]) {
                _index = index;
                assigned = true;
                return _index;
            }
        }
        require(assigned, "Didnt Find that element in live list, cannot scrub");
    }

    /// @dev View function to query a user's rewards they can claim via claimAllUserBonusTokens
    function checkClaimAllUserBonusTokens(
        address user,
        address[] memory targetBathTokens,
        address token
    ) public view returns (uint256 earnedAcrossPools) {
        for (uint256 index = 0; index < targetBathTokens.length; index++) {
            address targetBT = targetBathTokens[index];
            address targetBathBuddy = IBathToken(targetBT).bathBuddy();
            uint256 earned = IBathBuddy(targetBathBuddy).earned(user, token);
            earnedAcrossPools += earned;
        }
    }

    //============================= SWAP =============================

    function multiswap(
        address[][] memory routes,
        uint256[] memory pay_amts,
        uint256[] memory buy_amts_min,
        address to
    ) public {
        for (uint256 i = 0; i < routes.length; ++i) {
            swap(pay_amts[i], buy_amts_min[i], routes[i], to);
        }
    }

    /// @dev This function lets a user swap from route[0] -> route[last] at some minimum expected rate
    /// @dev pay_amt - amount to be swapped away from msg.sender of *first address in path*
    /// @dev buy_amt_min - target minimum received of *last address in path*
    function swap(
        uint256 pay_amt,
        uint256 buy_amt_min,
        address[] memory route, // First address is what is being payed, Last address is what is being bought
        address to
    ) public beGoneReentrantScum returns (uint256) {
        /// @dev get the EXACT amount needed to pay on a first iteration
        uint256 _payWithFee = _calcAmountAfterFee(pay_amt, false);
        uint _amount = RubiconMarket(RubiconMarketAddress).calculateFees(
            _payWithFee,
            true
        );

        //**User must approve this contract first**
        //transfer needed amount here first
        IERC20(route[0]).safeTransferFrom(msg.sender, address(this), _amount);

        // uint modifiedPayAmount = _calcAmountAfterFee(pay_amt, false);
        return _swap(pay_amt, buy_amt_min, route, to);
    }

    // ** Native ETH Wrapper Functions **
    /// @dev WETH wrapper functions to obfuscate WETH complexities from ETH holders
    function buyAllAmountWithETH(
        IERC20 buy_gem,
        uint256 buy_amt,
        uint256 max_fill_amount
    ) external payable beGoneReentrantScum returns (uint256 fill) {
        address _weth = address(wethAddress);
        uint256 _before = IERC20(_weth).balanceOf(address(this));
        uint feeInclusiveAmount = _calcAmountAfterFee(max_fill_amount, true);
        require(
            msg.value == feeInclusiveAmount,
            "must send as much ETH as max_fill_amount + FEE"
        );
        IWETH(wethAddress).deposit{value: feeInclusiveAmount}(); // Pay with native ETH -> WETH

        if (
            IWETH(wethAddress).allowance(address(this), RubiconMarketAddress) <
            feeInclusiveAmount
        ) {
            approveAssetOnMarket(wethAddress);
        }

        // An amount in WETH
        fill = RubiconMarket(RubiconMarketAddress).buyAllAmount(
            buy_gem,
            buy_amt,
            IERC20(wethAddress),
            max_fill_amount
        );
        IERC20(buy_gem).safeTransfer(msg.sender, fill);

        uint256 _after = IERC20(_weth).balanceOf(address(this));
        uint256 delta = _after - _before;

        // Return unspent coins to sender
        if (delta > 0) {
            IWETH(wethAddress).withdraw(delta);
            // msg.sender.transfer(delta);
            (bool success, ) = msg.sender.call{value: delta}("");
            require(success, "Transfer failed.");
        }
    }

    // Paying IERC20 to buy native ETH
    function buyAllAmountForETH(
        uint256 buy_amt,
        IERC20 pay_gem,
        uint256 max_fill_amount
    ) external beGoneReentrantScum returns (uint256 fill) {
        uint256 _before = pay_gem.balanceOf(address(this));
        IERC20(pay_gem).safeTransferFrom(
            msg.sender,
            address(this),
            _calcAmountAfterFee(max_fill_amount, true)
        ); //transfer pay here

        if (
            pay_gem.allowance(address(this), RubiconMarketAddress) <
            max_fill_amount
        ) {
            approveAssetOnMarket(address(pay_gem));
        }

        fill = RubiconMarket(RubiconMarketAddress).buyAllAmount(
            IERC20(wethAddress),
            buy_amt,
            pay_gem,
            max_fill_amount
        );
        // the actual amount we get in the WETH form
        // buy_amt = _calcAmountAfterFee(buy_amt, false);
        IWETH(wethAddress).withdraw(buy_amt); // Fill in WETH

        uint256 _after = pay_gem.balanceOf(address(this));
        uint256 _delta = _after - _before;

        // Return unspent coins to sender
        if (_delta > 0) {
            IERC20(pay_gem).safeTransfer(msg.sender, _delta);
        }

        // msg.sender.transfer(buy_amt); // Return native ETH
        (bool success, ) = msg.sender.call{value: buy_amt}("");
        require(success, "Transfer failed.");

        return fill;
    }

    function sellAllAmountForETH(
        IERC20 pay_gem,
        uint256 pay_amt,
        // buy_gem = ETH,
        uint256 min_fill_amount
    ) external beGoneReentrantScum returns (uint256 fill) {
        address _weth = address(wethAddress);
        uint256 _before = pay_gem.balanceOf(address(this));

        // determine the EXACT amount needed to transfer in order
        // to be able to pay fees in the Market
        (, uint256 transferFromAmount) = RubiconMarket(RubiconMarketAddress)
            .getPayAmountWithFee(pay_gem, IERC20(_weth), min_fill_amount);

        IERC20(pay_gem).safeTransferFrom(
            msg.sender,
            address(this),
            transferFromAmount
        ); //transfer pay here

        if (
            pay_gem.allowance(address(this), RubiconMarketAddress) <
            transferFromAmount
        ) {
            approveAssetOnMarket(address(pay_gem));
        }
        // sell pay_gem and buy WETH
        fill = RubiconMarket(RubiconMarketAddress).sellAllAmount(
            pay_gem,
            pay_amt,
            IERC20(_weth),
            min_fill_amount
        );
        IWETH(_weth).withdraw(fill);

        uint256 _after = pay_gem.balanceOf(address(this));
        uint256 _delta = _after - _before;

        // Return unspent coins to sender
        if (_delta > 0) {
            IERC20(pay_gem).safeTransfer(msg.sender, _delta);
        }

        // transfer ETH to msg.sender
        (bool success, ) = msg.sender.call{value: fill}("");
        require(success, "Transfer failed.");

        return fill;
    }

    function sellAllAmountWithETH(
        //pay_gem = ETH,
        uint256 pay_amt,
        IERC20 buy_gem,
        uint256 min_fill_amount
    ) external payable beGoneReentrantScum returns (uint256 fill) {
        address _weth = address(wethAddress);
        uint256 _before = IERC20(_weth).balanceOf(address(this));

        // determine how much ETH it's needed to send, in order
        // to be able to pay fees in the Market
        (, uint256 _msgValue) = RubiconMarket(RubiconMarketAddress)
            .getPayAmountWithFee(IERC20(_weth), buy_gem, min_fill_amount);

        require(msg.value == _msgValue, "must send as much ETH as _msgValue");
        IWETH(wethAddress).deposit{value: _msgValue}(); // Pay with native ETH -> WETH

        if (
            IWETH(wethAddress).allowance(address(this), RubiconMarketAddress) <
            _msgValue
        ) {
            approveAssetOnMarket(wethAddress);
        }

        // sell weth for buy_gem
        fill = RubiconMarket(RubiconMarketAddress).sellAllAmount(
            IERC20(_weth),
            pay_amt,
            buy_gem,
            min_fill_amount
        );
        IERC20(buy_gem).safeTransfer(msg.sender, fill);

        uint256 _after = IERC20(_weth).balanceOf(address(this));
        uint256 delta = _after - _before;

        // Return unspent coins to sender
        if (delta > 0) {
            IWETH(wethAddress).withdraw(delta);
            // msg.sender.transfer(delta);
            (bool success, ) = msg.sender.call{value: delta}("");
            require(success, "Transfer failed.");
        }
    }

    function swapWithETH(
        uint256 pay_amt,
        uint256 buy_amt_min,
        address[] calldata route, // First address is what is being payed, Last address is what is being bought
        address to
    ) external payable beGoneReentrantScum returns (uint256) {
        require(route[0] == wethAddress, "Initial value in path not WETH");
        require(
            msg.value == pay_amt,
            "must send enough native ETH to pay as weth and account for fee"
        );
        IWETH(wethAddress).deposit{value: pay_amt}();

        return _swap(pay_amt, buy_amt_min, route, to);
    }

    function swapForETH(
        uint256 pay_amt,
        uint256 buy_amt_min,
        address[] calldata route // First address is what is being payed, Last address is what is being bought
    ) external beGoneReentrantScum returns (uint256 fill) {
        require(
            route[route.length - 1] == wethAddress,
            "target of swap is not WETH"
        );

        /// @dev get the EXACT amount needed to pay on a first iteration
        uint256 _payWithFee = _calcAmountAfterFee(pay_amt, false);
        uint _amount = RubiconMarket(RubiconMarketAddress).calculateFees(
            _payWithFee,
            true
        );
        IERC20(route[0]).safeTransferFrom(msg.sender, address(this), _amount);

        fill = _swap(pay_amt, buy_amt_min, route, address(this));

        IWETH(wethAddress).withdraw(fill);
        // msg.sender.transfer(fill);
        (bool success, ) = msg.sender.call{value: fill}("");
        require(success, "Transfer failed.");
    }

    //============================= OFFERS =============================

    // Pay in native ETH
    // function offerWithETH(
    //     uint256 pay_amt, //maker (ask) sell how much
    //     // IERC20 nativeETH, //maker (ask) sell which token
    //     uint256 buy_amt, //maker (ask) buy how much
    //     IERC20 buy_gem, //maker (ask) buy which token
    //     uint256 pos, //position to insert offer, 0 should be used if unknown
    //     address recipient // the recipient of the fill
    // ) external payable returns (uint256) {
    //     require(
    //         msg.value == pay_amt,
    //         "didnt send enough native ETH for WETH offer"
    //     );

    //     uint256 _before = IERC20(buy_gem).balanceOf(address(this));

    //     IWETH(wethAddress).deposit{value: pay_amt}();

    //     if (
    //         IWETH(wethAddress).allowance(address(this), RubiconMarketAddress) <
    //         pay_amt
    //     ) {
    //         approveAssetOnMarket(wethAddress);
    //     }
    //     uint256 id = RubiconMarket(RubiconMarketAddress).offer(
    //         pay_amt,
    //         IERC20(wethAddress),
    //         buy_amt,
    //         buy_gem,
    //         pos,
    //         address(this), // router is owner of the offer
    //         recipient
    //     );

    //     // Track the user's order so they can cancel it
    //     userNativeAssetOrders[msg.sender].push(id);

    //     uint256 _after = IERC20(buy_gem).balanceOf(address(this));
    //     if (_after > _before) {
    //         //return any potential fill amount on the offer
    //         IERC20(buy_gem).safeTransfer(recipient, _after - _before);
    //     }
    //     return id;
    // }

    // // Pay in native ETH
    // function offerForETH(
    //     uint256 pay_amt, //maker (ask) sell how much
    //     IERC20 pay_gem, //maker (ask) sell which token
    //     uint256 buy_amt, //maker (ask) buy how much
    //     // IERC20 nativeETH, //maker (ask) buy which token
    //     uint256 pos, //position to insert offer, 0 should be used if unknown
    //     address recipient // the recipient of the fill
    // ) external beGoneReentrantScum returns (uint256) {
    //     IERC20(pay_gem).safeTransferFrom(msg.sender, address(this), pay_amt);

    //     uint256 _before = IERC20(wethAddress).balanceOf(address(this));

    //     if (pay_gem.allowance(address(this), RubiconMarketAddress) < pay_amt) {
    //         approveAssetOnMarket(address(pay_gem));
    //     }

    //     uint256 id = RubiconMarket(RubiconMarketAddress).offer(
    //         pay_amt,
    //         pay_gem,
    //         buy_amt,
    //         IERC20(wethAddress),
    //         pos,
    //         address(this), // router is owner of an offer
    //         recipient
    //     );

    //     // Track the user's order so they can cancel it
    //     userNativeAssetOrders[msg.sender].push(id);

    //     uint256 _after = IERC20(wethAddress).balanceOf(address(this));
    //     if (_after > _before) {
    //         //return any potential fill amount on the offer as native ETH
    //         uint256 delta = _after - _before;
    //         IWETH(wethAddress).withdraw(delta);
    //         // msg.sender.transfer(delta);
    //         (bool success, ) = payable(recipient).call{value: delta}("");
    //         require(success, "Transfer failed.");
    //     }

    //     return id;
    // }

    // // Cancel an offer made in WETH
    // function cancelForETH(
    //     uint256 id
    // ) external beGoneReentrantScum returns (bool outcome) {
    //     uint256 indexOrFail = getIndexFromElement(
    //         id,
    //         userNativeAssetOrders[msg.sender]
    //     );
    //     /// @dev Verify that the offer the user is trying to cancel is their own
    //     require(
    //         userNativeAssetOrders[msg.sender][indexOrFail] == id,
    //         "You did not provide an Id for an offer you own"
    //     );

    //     (uint256 pay_amt, IERC20 pay_gem, , ) = RubiconMarket(
    //         RubiconMarketAddress
    //     ).getOffer(id);
    //     require(
    //         address(pay_gem) == wethAddress,
    //         "trying to cancel a non WETH order"
    //     );
    //     // Cancel order and receive WETH here in amount of pay_amt
    //     outcome = RubiconMarket(RubiconMarketAddress).cancel(id);
    //     IWETH(wethAddress).withdraw(pay_amt);
    //     // msg.sender.transfer(pay_amt);
    //     (bool success, ) = msg.sender.call{value: pay_amt}("");
    //     require(success, "Transfer failed.");
    // }

    //============================= POOLS =============================

    // Deposit native ETH -> WETH pool
    function depositWithETH(
        uint256 amount,
        address bathToken,
        address to
    ) external payable beGoneReentrantScum returns (uint256 newShares) {
        address target = CErc20Storage(bathToken).underlying();
        require(target == wethAddress, "target pool not weth pool");
        require(msg.value == amount, "didnt send enough eth");

        if (IERC20(target).allowance(address(this), bathToken) == 0) {
            IERC20(target).approve(bathToken, amount);
        }

        IWETH(wethAddress).deposit{value: amount}();
        IERC20(wethAddress).approve(bathToken, amount);
        require(CErc20Interface(bathToken).mint(amount) == 0, "mint failed");

        newShares = IERC20(bathToken).balanceOf(address(this));
        /// @dev v2 bathTokens shouldn't be sent to this contract from anywhere other than this function
        IERC20(bathToken).safeTransfer(to, newShares);
        require(
            IERC20(bathToken).balanceOf(address(this)) == 0,
            "bath tokens stuck"
        );
    }

    // Withdraw native ETH <- WETH pool
    function withdrawForETH(
        uint256 shares,
        address bathToken
    ) external beGoneReentrantScum returns (uint256 withdrawnWETH) {
        address target = CErc20Storage(bathToken).underlying();
        require(target == wethAddress, "target pool not weth pool");

        uint256 startingWETHBalance = IERC20(wethAddress).balanceOf(
            address(this)
        );

        IERC20(bathToken).transferFrom(msg.sender, address(this), shares);
        require(
            CErc20Interface(bathToken).redeem(shares) == 0,
            "redeem failed"
        );

        uint256 postWithdrawWETH = IERC20(wethAddress).balanceOf(address(this));
        require(postWithdrawWETH > startingWETHBalance);

        withdrawnWETH = postWithdrawWETH.sub(startingWETHBalance);
        IWETH(wethAddress).withdraw(withdrawnWETH);

        //Send back withdrawn native eth to sender
        // msg.sender.transfer(withdrawnWETH);
        (bool success, ) = msg.sender.call{value: withdrawnWETH}("");
        require(success, "Transfer failed.");
    }

    
    // *** V1 Functionality for backwards compatibility ***
    // Deposit native ETH -> WETH pool
    function depositWithETHv1(uint256 amount, address targetPool)
        external
        payable
        beGoneReentrantScum
        returns (uint256 newShares)
    {
        IERC20 target = IBathToken(targetPool).underlyingToken();
        require(target == IERC20(wethAddress), "target pool not weth pool");
        require(msg.value == amount, "didnt send enough eth");

        if (target.allowance(address(this), targetPool) == 0) {
            target.safeApprove(targetPool, amount);
        }

        IWETH(wethAddress).deposit{value: amount}();
        newShares = IBathToken(targetPool).deposit(amount);
        //Send back bathTokens to sender
        IERC20(targetPool).safeTransfer(msg.sender, newShares);
    }

    // Withdraw native ETH <- WETH pool
    function withdrawForETHv1(uint256 shares, address targetPool)
        external
        payable
        beGoneReentrantScum
        returns (uint256 withdrawnWETH)
    {
        IERC20 target = IBathToken(targetPool).underlyingToken();
        require(target == IERC20(wethAddress), "target pool not weth pool");

        uint256 startingWETHBalance = IERC20(wethAddress).balanceOf(
            address(this)
        );
        IBathToken(targetPool).transferFrom(msg.sender, address(this), shares);
        withdrawnWETH = IBathToken(targetPool).withdraw(shares);
        uint256 postWithdrawWETH = IERC20(wethAddress).balanceOf(address(this));
        require(
            withdrawnWETH == (postWithdrawWETH.sub(startingWETHBalance)),
            "bad WETH value hacker"
        );
        IWETH(wethAddress).withdraw(withdrawnWETH);

        //Send back withdrawn native eth to sender
        // msg.sender.transfer(withdrawnWETH);
        (bool success, ) = msg.sender.call{value: withdrawnWETH}("");
        require(success, "Transfer failed.");
    }

    //============================= HELPERS =============================

    // function for infinite approvals of Rubicon Market
    function approveAssetOnMarket(address toApprove) internal {
        require(
            started &&
                RubiconMarketAddress != address(this) &&
                RubiconMarketAddress != address(0),
            "Router not initialized"
        );
        // Approve exchange
        IERC20(toApprove).approve(
            RubiconMarketAddress,
            type(uint256).max
        );
    }

    //============================= INTERNALS =============================

    // Internal function requires that ERC20s are here before execution
    function _swap(
        uint256 pay_amt,
        uint256 buy_amt_min,
        address[] memory route, // First address is what is being payed, Last address is what is being bought
        address to // Recipient of swap outputs!
    ) internal returns (uint256) {
        require(route.length > 1, "Not enough hop destinations!");

        address _market = RubiconMarketAddress;
        uint256 currentAmount;

        for (uint256 i = 0; i < route.length - 1; ++i) {
            (address input, address output) = (route[i], route[i + 1]);

            uint256 _pay = i == 0 ? pay_amt : currentAmount;

            if (IERC20(input).allowance(address(this), _market) < _pay) {
                approveAssetOnMarket(input);
            }

            // fillAmount already with fee deducted
            uint256 fillAmount = RubiconMarket(_market).sellAllAmount(
                IERC20(input),
                _calcAmountAfterFee(_pay, false),
                IERC20(output),
                0 //naively assume no fill_amt here for loop purposes?
            );

            currentAmount = fillAmount;
        }
        require(currentAmount >= buy_amt_min, "didnt clear buy_amt_min");

        // send tokens back to sender if not keeping here
        if (to != address(this)) {
            IERC20(route[route.length - 1]).safeTransfer(to, currentAmount);
        }

        emit emitSwap(
            to,
            route[0],
            route[route.length - 1],
            keccak256(abi.encodePacked(route[0], route[route.length - 1])),
            pay_amt,
            currentAmount,
            buy_amt_min
        );

        return currentAmount;
    }

    function _calcAmountAfterFee(
        uint256 amount,
        bool direction
    ) internal view returns (uint256) {
        return
            RubiconMarket(RubiconMarketAddress).calculateFees(
                amount,
                direction
            );
    }
}

