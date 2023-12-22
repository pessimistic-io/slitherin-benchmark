// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./INonfungiblePositionManager.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Address.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import "./IQuoter.sol";
import "./IWETH9.sol";
import "./TickMath.sol";
import "./ISwapRouter.sol";
import "./LiquidityAmounts.sol";

contract RangePositionManager is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;

    uint256 public currentTokenId;
    uint128 public totalLiquidity;

    int24 internal currentTickLower;
    int24 internal currentTickUpper;

    address internal immutable WETH;
    address internal token0;
    address internal token1;
    uint24 internal immutable fee;

    // Maximum acceptable price deviation threshold in basis points (1 basis point = 0.01%, 50 basis points = 0.5%, 100 basis points = 1%)
    int24 public tickMoveThreshold;

    // indicates if the mint and increase liquidity is locked
    bool public isLocked;

    // indicates if moveRange check is on
    bool public checkMoveRangeDisabled;

    // indicates the earn cooldown period
    uint public earnCooldownPeriod;

    address internal yieldManager;
    address public owner;
    address private _pendingOwner;
    address public feeReceiver;
    address private _pendingFeeReceiver;
    INonfungiblePositionManager public positionManager;
    IUniswapV3Pool internal immutable uniswapV3Pool;
    IUniswapV3Factory internal uniswapV3Factory;
    ISwapRouter internal uniswapV3Router;
    IQuoter public uniswapQuoter;

    address[] public userList;
    uint public maxUsers;

    // structs
    struct UserInfo {
        uint liquidity;
        uint earnTimestamp;
        uint token0Balance;
        uint token1Balance;
        uint leftOverToken0Balance;
        uint leftOverToken1Balance;
    }

    // struct for handling the variables in moveRange
    struct MoveRangeParams {
        uint160 sqrtPriceX96;
        uint decreaseAmount0;
        uint decreaseAmount1;
        uint amount0;
        uint amount1;
        int24 currentTick;
        int24 tickSpace;
        int24 currentTickLowerInterpolated;
        int24 currentTickUpperInterpolated;
        int24 newTickUpper;
        int24 newTickLower;
        uint160 sqrtPriceLimitX96;
        uint160 sqrtRatioA;
        uint160 sqrtRatioB;
        address tokenIn;
        address tokenOut;
        uint amountIn;
        uint amountOutQuote;
        uint amountOutMinimum;
    }

    // mappings
    mapping(address => UserInfo) public userMapping;
    mapping(address => bool) internal isUser;
    mapping(address => bool) public moveRangeAddresses;

    // only owner modifier
    modifier onlyOwner {
        _onlyOwner();
        _;
    }

    // only owner view
    function _onlyOwner() private view {
        require(msg.sender == owner || msg.sender == address(this), "Only the contract owner may perform this action");
    }

    // events
    event Mint(uint amount0, uint amount1, uint liquidity, uint tokenId, address user);
    event IncreaseLiquidity(uint amount0, uint amount1, uint liquidity, address user);
    event RemovedLiquidity(uint amount0, uint amount1, uint liquidity, address user);
    event FeesWithdrawn(uint amount0, uint amount1, address user);
    event NewSponsor(address sponsor, address client);
    event NewYieldManager(address yieldManager);
    event NewOwner(address owner);
    event Locked(bool locked);
    event MovedRange(int24 tickLower, int24 tickUpper);
    event NewTickMoveThreshold(int24 tickMove);
    event CheckMoveRangeDisabled(bool checkDisabled);
    event MoveAddressUpdated(address mover, bool status);
    event NewFeeReceiver(address newFeeReceiver);
    event NewEarnCoolDownPeriod(uint newEarnCooldownPeriod);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event FeeReceiverTransferStarted(address indexed previousFeeReceiver, address indexed newFeeReceiver);
    event NewMaxUsers(uint maxUsers);

    constructor(
        address _owner,
        address _positionManager,
        address _uniswapV3Router,
        address _uniswapQuoter,
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickMoveThreshold,
        address _yieldManager,
        uint _maxUsers
    ){
        require(_owner != address(0), "Owner cant be zero address");
        require(_token1 != address(0) && _token0 != address(0), "Zero address for tokens");
        require(_yieldManager != address(0), "Zero address for yieldManager");
        require(_tickMoveThreshold <= 10000, "_tickMoveThreshold too big");

        owner = _owner;
        feeReceiver = _owner;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;

        positionManager = INonfungiblePositionManager(_positionManager);
        uniswapV3Router = ISwapRouter(_uniswapV3Router);
        uniswapQuoter = IQuoter(_uniswapQuoter);
        uniswapV3Factory = IUniswapV3Factory(positionManager.factory());
        uniswapV3Pool = IUniswapV3Pool(uniswapV3Factory.getPool(token0, token1, fee));
        WETH = positionManager.WETH9();

        tickMoveThreshold = _tickMoveThreshold;
        yieldManager = _yieldManager;

        maxUsers = _maxUsers;
    }

    /// Function for the first mint of the initial position nft
    /// @dev mints the first initial position NFT, can only be called by the owner
    /// @dev this contract accepts native ETH and converts it to WETH
    /// @dev WETH deposits are not allowed (only ETH)
    /// @param tickLower the lower tick
    /// @param tickUpper the upper tick
    /// @param amountDesired0 the amount of token0 desired
    /// @param amountDesired1 the amount of token1 desired
    /// @param slippagePercent slippage amount for protection
    function mintOwner(
        int24 tickLower,
        int24 tickUpper,
        uint amountDesired0,
        uint amountDesired1,
        uint slippagePercent
    )
    external payable onlyOwner nonReentrant {
        require(totalLiquidity == 0, "owner mint can only be triggered with 0 liquidity");
        mint(tickLower, tickUpper, amountDesired0, amountDesired1, slippagePercent, false);
    }

    /// Checks if range can be moved
    /// @dev checks if the range position can be moved
    /// returns a bool indicating if position can be moved or not
    function canMoveRange() public view returns (bool) {
        // if check is disabled we can always move
        if (checkMoveRangeDisabled) {
            return true;
        }

        // get the current tick
        (,int24 currentTick,,,,,) = uniswapV3Pool.slot0();

        // delta can never be a negative number
        int256 delta = int256(currentTickUpper) - int256(currentTickLower);
        int256 hardLimitTickUpper = int256(currentTickUpper) - (tickMoveThreshold * delta / 10000);
        int256 hardLimitTickLower = int256(currentTickLower) + (tickMoveThreshold * delta / 10000);

        return currentTick > hardLimitTickUpper || currentTick < hardLimitTickLower;
    }

    /// Swaps one token for another
    /// @dev performs a swap with a Uniswap V3 pool
    /// @param tokenIn the input token
    /// @param tokenOut the output token
    /// @param amountIn the input amount
    /// @param slippagePercent the slippage in percent
    /// returns the output amount of the desired token
    function swap(address tokenIn, address tokenOut, uint amountIn, uint slippagePercent) internal returns (uint256 amountOut) {
        uint amountOutQuote = uniswapQuoter.quoteExactInputSingle(tokenIn, tokenOut, fee, amountIn, 0);
        uint amountOutMinimum = amountOutQuote - (amountOutQuote * slippagePercent / 10000);

        // Perform the token swap using Uniswap V3 SwapRouter (example code, comment only)
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum,
            sqrtPriceLimitX96: 0
        });

        // Perform the token approval for the swap
        if (tokenIn != WETH) {
            IERC20(tokenIn).safeApprove(address(uniswapV3Router), 0);
            IERC20(tokenIn).safeApprove(address(uniswapV3Router), amountIn);
        }

        // The call to `exactInputSingle` executes the swap.
        amountOut = uniswapV3Router.exactInputSingle{value: tokenIn == WETH ? amountIn : 0}(swapParams);

        if (tokenOut == WETH) {
            IWETH9(WETH).approve(WETH, 0);
            IWETH9(WETH).approve(WETH, IERC20(WETH).balanceOf(address(this)));
            IWETH9(WETH).withdraw(IERC20(WETH).balanceOf(address(this)));
        }
    }

    /// View function to get the amount for ticks onchain
    /// @dev checks for liquidity amount s on chain
    /// @param tickLower the lower tick
    /// @param tickUpper the upper tick
    /// @param liquidity the amount of liquidity
    /// returns the output amount for token0 and token1
    function getAmountsForTicks(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external view returns (uint256 amount0, uint256 amount1) {
        (uint160 sqrtPriceX96,,,,,,) = uniswapV3Pool.slot0();
        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, TickMath.getSqrtRatioAtTick(tickLower), TickMath.getSqrtRatioAtTick(tickUpper), liquidity);
    }

    /// function for moving range
    /// @dev this function is used to move the liquidity ranges (lower tick, upper tick). If possible (within the threshold)
    /// @dev it is possible to call this function. It will decrease all liquidity from the position, swap tokens in a ratio given in the parameter
    /// @dev and then mint a new position using this tokens swapped. Users will get the share of the new liquidity pro rata
    /// @param tickLower the new lower tick
    /// @param tickUpper the new upper tick
    /// @param tokenForRatios the token to be swapped in firstly
    /// @param amountToSwap the amount to be swapped from the tokenForRatios
    /// @param slippagePercent the slippage setting
    function moveRange
    (
        int24 tickLower,
        int24 tickUpper,
        address tokenForRatios,
        uint amountToSwap,
        uint slippagePercent
    )
    external nonReentrant
    {
        require(moveRangeAddresses[msg.sender], "not allowed to move range");
        require(currentTokenId != 0, 'Not initialized');
        require(canMoveRange(), "Not allowed to move range");
        require(slippagePercent <= 10000, "slippage setting too high");
        require(tokenForRatios == token0 || tokenForRatios == token1, "wrong token argument");

        // collect fees
        collect(0, 0);

        MoveRangeParams memory params;

        // calculate the amount of token0 and token1 based on the percentage of liquidity to be removed
        (params.sqrtPriceX96,params.currentTick,,,,,) = uniswapV3Pool.slot0();

        params.sqrtRatioA = TickMath.getSqrtRatioAtTick(currentTickLower);
        params.sqrtRatioB = TickMath.getSqrtRatioAtTick(currentTickUpper);
        (params.decreaseAmount0, params.decreaseAmount1) = LiquidityAmounts.getAmountsForLiquidity(params.sqrtPriceX96, params.sqrtRatioA, params.sqrtRatioB, totalLiquidity);

        // decrease to 0
        (params.amount0, params.amount1) = decreaseLiquidity(params.decreaseAmount0, params.decreaseAmount1, slippagePercent, totalLiquidity, address(this), true);

        // burn the position
        positionManager.burn(currentTokenId);

        // get correct input params
        params.tokenIn = (tokenForRatios == token0) ? token1 : token0; // Token to swap from (depends on the token we get from the input)
        params.tokenOut = (tokenForRatios == token0) ? token0 : token1; // Token to receive (opposite of tokenIn)
        params.amountIn = (tokenForRatios == token0) ? params.amount1 : params.amount0; // Amount to swap from (either amount0 or amount1)
        uint returnFromSwap;

        if (params.amountIn > 0) {
            returnFromSwap = swap(params.tokenIn, params.tokenOut, params.amountIn, slippagePercent);
        }

        if (tokenForRatios == token0) {
            returnFromSwap = returnFromSwap + params.amount0;
        }
        else {
            returnFromSwap = returnFromSwap + params.amount1;
        }

        // The call to `exactInputSingle` executes the swap.
        uint returnFromSwapFinal = swap(params.tokenOut, params.tokenIn, amountToSwap, slippagePercent);

        // get amounts
        uint amount0Before;
        uint amount1Before;

        if (token0 == WETH) {
            amount0Before = address(this).balance;
        } else {
            amount0Before = IERC20(token0).balanceOf(address(this));
        }

        if (token1 == WETH) {
            amount1Before = address(this).balance;
        } else {
            amount1Before = IERC20(token1).balanceOf(address(this));
        }

        uint token0check = tokenForRatios == token0 ? returnFromSwap - amountToSwap : returnFromSwapFinal;
        uint token1check = tokenForRatios == token0 ? returnFromSwapFinal : returnFromSwap - amountToSwap;

        // mint new position
        mint(
            tickLower,
            tickUpper,
            token0check,
            token1check,
            slippagePercent,
            true
        );

        // get amounts after mint of token0 and 1 on the contract
        uint amount0After;
        uint amount1After;

        if (token0 == WETH) {
            amount0After = address(this).balance;
        } else {
            amount0After = IERC20(token0).balanceOf(address(this));
        }

        if (token1 == WETH) {
            amount1After = address(this).balance;
        } else {
            amount1After = IERC20(token1).balanceOf(address(this));
        }

        require(amount0Before - (token0check * slippagePercent / 10000)  >= amount0After, "Slippage amount0 diff");
        require(amount1Before - (token1check * slippagePercent / 10000) >= amount1After, "Slippage amount1 diff");

        emit MovedRange(tickLower, tickUpper);
    }


    /// Internal mint function
    /// @dev mints position NFTs according to the params. Can be a first time mint from the owner, or moveRange mint
    /// @param tickLower the lower tick
    /// @param tickUpper the upper tick
    /// @param amountDesired0 the amount of token0 desired
    /// @param amountDesired1 the amount of token1 desired
    /// @param slippagePercent slippage amount for protection
    /// @param contractCall indicated if it is a moveRange call (coming from the contract itself)
    function mint(
        int24 tickLower,
        int24 tickUpper,
        uint amountDesired0,
        uint amountDesired1,
        uint slippagePercent,
        bool contractCall
    ) internal {
        // check if locked
        require(!isLocked, "Locked for minting");

        // get mint decreaseParams
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams(
            {
                token0 : token0,
                token1 : token1,
                fee : fee,
                tickLower : tickLower,
                tickUpper : tickUpper,
                amount0Desired : amountDesired0,
                amount1Desired : amountDesired1,
                amount0Min : amountDesired0 - (amountDesired0 * slippagePercent / 10000),
                amount1Min : amountDesired1 - (amountDesired1 * slippagePercent / 10000),
                recipient : address(this),
                deadline : block.timestamp
            }
        );

        // handle the approvals for ERC20 tokens
        if (mintParams.token0 != WETH) {
            IERC20(mintParams.token0).safeApprove(address(positionManager), 0);
            IERC20(mintParams.token0).safeApprove(address(positionManager), mintParams.amount0Desired);
        }

        if (mintParams.token1 != WETH) {
            IERC20(mintParams.token1).safeApprove(address(positionManager), 0);
            IERC20(mintParams.token1).safeApprove(address(positionManager), mintParams.amount1Desired);
        }

        // define output variables for later usage
        uint256 tokenId;
        uint256 amount0;
        uint256 amount1;
        uint128 liquidity;

        // call this if it is a reposition call
        if (contractCall) {

            (tokenId, liquidity, amount0, amount1) = positionManager.mint{value : token0 == WETH ? mintParams.amount0Desired : (token1 == WETH ? mintParams.amount1Desired : 0)}(mintParams);
            positionManager.refundETH();

            uint amount0Diff = amountDesired0 - amount0;
            uint amount1Diff = amountDesired1 - amount1;

            require(totalLiquidity != 0, "totalLiquidity divisor is zero");
            require(liquidity != 0, "liquidity divisor is zero");

            // update user percentages
            uint userListLength = userList.length;
            for (uint i = 0; i < userListLength; i++) {
                UserInfo storage userElement = userMapping[userList[i]];
                userElement.liquidity = userElement.liquidity * liquidity / totalLiquidity;

                if (amount0Diff > 0) {
                    userElement.leftOverToken0Balance += amount0Diff * userElement.liquidity / liquidity;
                }
                if (amount1Diff > 0) {
                    userElement.leftOverToken1Balance += amount1Diff * userElement.liquidity / liquidity;
                }
            }
        }

            // sender is not the contract, first owner call
        else {
            (tokenId, liquidity, amount0, amount1) = positionManager.mint{value : msg.value}(mintParams);
            // housekeeping for first mint
            positionManager.refundETH();
            // sweep the remaining tokens
            if (token0 != WETH) {
                positionManager.sweepToken(token0, 0, address(this));
            }
            if (token1 != WETH) {
                positionManager.sweepToken(token1, 0, address(this));
            }

            // refunds
            if (token0 == WETH && (address(this).balance > 0)) {
                payable(msg.sender).sendValue(address(this).balance);
            }
            if (token1 == WETH && (address(this).balance > 0)) {
                payable(msg.sender).sendValue(address(this).balance);
            }
            if (token0 != WETH && IERC20(token0).balanceOf(address(this)) > 0) {
                IERC20(token0).safeTransfer(msg.sender, IERC20(token0).balanceOf(address(this)));
            }
            if (token1 != WETH && IERC20(token1).balanceOf(address(this)) > 0) {
                IERC20(token1).safeTransfer(msg.sender, IERC20(token1).balanceOf(address(this)));
            }

            //add owner init as user used for owner decrease after potential lock
            if (!isUser[msg.sender]) {
                // update user mapping
                UserInfo storage userElement = userMapping[msg.sender];
                userElement.liquidity += liquidity;

                // push the unique item to the array
                userList.push(msg.sender);
                isUser[msg.sender] = true;
            }
        }

        totalLiquidity = liquidity;
        currentTokenId = tokenId;
        currentTickUpper = tickUpper;
        currentTickLower = tickLower;

        emit Mint(amount0, amount1, liquidity, currentTokenId, msg.sender);
    }

    /// function for increasing liquidity
    /// @dev for increasing liquidity, also sets the sponsor if new user
    /// @param amountDesired0 the minimum amount to use of token0
    /// @param amountDesired1 the minimum amount to use of token1
    /// @param slippagePercent the slippage setting
    /// @param sponsor the address of the sponsor
    function increaseLiquidity(
        uint amountDesired0,
        uint amountDesired1,
        uint slippagePercent,
        address sponsor
    )
    external
    payable
    nonReentrant
    {
        // check if locked
        require(!isLocked, "Locked for increasing liquidity");
        require(isUser[msg.sender] || userList.length < maxUsers, "Max users reached");

        // set new sponsor if needed
        if (sponsor != address(0) && sponsor != msg.sender && IYieldManager(yieldManager).getAffiliate(msg.sender) == address(0)) {
            IYieldManager(yieldManager).setAffiliate(msg.sender, sponsor);
            emit NewSponsor(sponsor, msg.sender);
        }

        // get increase params
        INonfungiblePositionManager.IncreaseLiquidityParams memory increaseParams = INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId : currentTokenId,
            amount0Desired : amountDesired0,
            amount1Desired : amountDesired1,
            amount0Min : amountDesired0 - (amountDesired0 * slippagePercent / 10000),
            amount1Min : amountDesired1 - (amountDesired1 * slippagePercent / 10000),
            deadline : block.timestamp
        });

        // handle approvals
        if (token0 != WETH) {
            IERC20(token0).safeTransferFrom(msg.sender, address(this), amountDesired0);
            IERC20(token0).safeApprove(address(positionManager), 0);
            IERC20(token0).safeApprove(address(positionManager), amountDesired0);
        }

        if (token1 != WETH) {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amountDesired1);
            IERC20(token1).safeApprove(address(positionManager), 0);
            IERC20(token1).safeApprove(address(positionManager), amountDesired1);
        }

        (uint128 liquidity, uint256 amount0, uint256 amount1) = positionManager.increaseLiquidity{value : msg.value}(increaseParams);
        positionManager.refundETH();

        // update user mapping
        UserInfo storage userElement = userMapping[msg.sender];
        userElement.liquidity += liquidity;

        // users will only be considered for fees after earnCooldownPeriod
        userElement.earnTimestamp = block.timestamp + earnCooldownPeriod;

        // check against the mapping
        if (!isUser[msg.sender]) {
            // push the unique item to the array
            userList.push(msg.sender);
            isUser[msg.sender] = true;
        }

        // send back tokens
        if (token0 == WETH && (msg.value - amount0 > 0)) {
            payable(msg.sender).sendValue(msg.value - amount0);
        }
        if (token1 == WETH && (msg.value - amount1 > 0)) {
            payable(msg.sender).sendValue(msg.value - amount1);
        }
        if (token0 != WETH && amountDesired0 - amount0 > 0) {
            IERC20(token0).safeTransfer(msg.sender, amountDesired0 - amount0);
        }
        if (token1 != WETH && amountDesired1 - amount1 > 0) {
            IERC20(token1).safeTransfer(msg.sender, amountDesired1 - amount1);
        }

        totalLiquidity += liquidity;
        emit IncreaseLiquidity(amount0, amount1, liquidity, msg.sender);
    }


    /// function for decreasing liquidity, for msg.sender
    /// @dev for decreasing liquidity, for msg.sender
    /// @param amount0Min the minimum amount to receive of token0
    /// @param amount1Min the minimum amount to receive of token1
    /// @param slippagePercent the slippage setting
    /// @param liquidity the amount of liquidity to be decreased
    function decreaseLiquidityUser(
        uint amount0Min,
        uint amount1Min,
        uint slippagePercent,
        uint128 liquidity
    )
    external
    nonReentrant
    {
        //get user element
        UserInfo storage userElement = userMapping[msg.sender];

        // check for liquidity
        require(liquidity <= userElement.liquidity);

        // perform decrease liquidity
        decreaseLiquidity(amount0Min, amount1Min, slippagePercent, liquidity, msg.sender, false);
    }

    /// function for decreasing liquidity, used by governance to force decrease of a specific user after x amount of time
    /// @dev for decreasing liquidity, used by governance to force decrease of a specific user after x amount of time
    /// @param amount0Min the minimum amount to receive of token0
    /// @param amount1Min the minimum amount to receive of token1
    /// @param slippagePercent the slippage setting
    /// @param liquidity the amount of liquidity to be decreased
    /// @param userToDecrease the user address to be decreased
    function decreaseLiquidityUserForce(
        uint amount0Min,
        uint amount1Min,
        uint slippagePercent,
        uint128 liquidity,
        address userToDecrease
    )
    external
    onlyOwner
    nonReentrant
    {
        //get user element
        UserInfo storage userElement = userMapping[userToDecrease];

        // check for liquidity
        require(liquidity <= userElement.liquidity);

        // perform decrease liquidity
        decreaseLiquidity(amount0Min, amount1Min, slippagePercent, liquidity, userToDecrease, false);
    }

    /// function for decreasing liquidity, internal, can be used for user decrease, forced decrease or internal new mint decrease
    /// @dev for decreasing liquidity, internal, can be used for user decrease, forced decrease or internal new mint decrease
    /// @param amount0Min the minimum amount to receive of token0
    /// @param amount1Min the minimum amount to receive of token1
    /// @param slippagePercent the slippage setting
    /// @param liquidity the amount of liquidity to be decreased
    /// @param userToDecrease the user address to be decreased
    /// @param contractCall indicated if call comes from inside the contract or user action
    /// @return amount0 the amount how much token0 we got as return
    /// @return amount1 the amount how much token1 we got as return
    function decreaseLiquidity(
        uint amount0Min,
        uint amount1Min,
        uint slippagePercent,
        uint128 liquidity,
        address userToDecrease,
        bool contractCall
    )
    internal
    returns
    (
        uint amount0,
        uint amount1
    )
    {
        // build decrease params
        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams = INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId : currentTokenId,
            liquidity : liquidity,
            amount0Min : amount0Min - (amount0Min * slippagePercent / 10000),
            amount1Min : amount1Min - (amount1Min * slippagePercent / 10000),
            deadline : block.timestamp
        });

        (amount0, amount1) = positionManager.decreaseLiquidity(decreaseParams);

        collect(amount0, amount1);

        if (!contractCall) {
            //get user element
            UserInfo storage userElement = userMapping[userToDecrease];
            // housekeeping
            userElement.liquidity -= liquidity;

            // if no liquidity we remove user
            if (userElement.liquidity == 0) {
                uint userListLength = userList.length;
                for (uint i = 0; i < userListLength; i++) {
                    if (userList[i] == userToDecrease) {
                        // Move the last element into the place to delete
                        userList[i] = userList[userListLength - 1];
                        // Remove the last element
                        userList.pop();
                        break;
                    }
                }
                isUser[userToDecrease] = false;
            }

            totalLiquidity -= liquidity;

            // fees
            // get user stats
            (, , uint val3,) = IYieldManager(yieldManager).getUserFactors(
                userToDecrease,
                0
            );

            uint mgmtFee0 = (val3 * amount0) / 100 / 100;
            uint sponsorFee0;
            uint mgmtFee1 = (val3 * amount1) / 100 / 100;
            uint sponsorFee1;

            // get sponsor
            address sponsor = IYieldManager(yieldManager).getAffiliate(userToDecrease);
            // get sponsor stats
            if (sponsor != address(0)) {
                (, uint sval2,,) = IYieldManager(yieldManager)
                    .getUserFactors(sponsor, 1);
                sponsorFee0 = (mgmtFee0 * sval2) / 100 / 100;
                mgmtFee0 -= sponsorFee0;
                sponsorFee1 = (mgmtFee1 * sval2) / 100 / 100;
                mgmtFee1 -= sponsorFee1;
            }
            // update user mapping
            UserInfo storage userElementOwner = userMapping[owner];

            // send back tokens
            if (token0 == WETH && (amount0 - mgmtFee0 - sponsorFee0 > 0)) {
                payable(userToDecrease).sendValue(amount0 - mgmtFee0 - sponsorFee0);
                userElementOwner.token0Balance += mgmtFee0;

                if (sponsor != address(0) && sponsorFee0 != 0) {
                    payable(sponsor).sendValue(sponsorFee0);
                }
            }
            if (token1 == WETH && (amount1 - mgmtFee1 - sponsorFee1 > 0)) {
                payable(userToDecrease).sendValue(amount1 - mgmtFee1 - sponsorFee1);
                userElementOwner.token1Balance += mgmtFee1;

                if (sponsor != address(0) && sponsorFee1 != 0) {
                    payable(sponsor).sendValue(sponsorFee1);
                }
            }
            if (token0 != WETH && amount0 - mgmtFee0 - sponsorFee0 > 0) {
                IERC20(token0).safeTransfer(userToDecrease, amount0 - mgmtFee0 - sponsorFee0);
                userElementOwner.token0Balance += mgmtFee0;

                if (sponsor != address(0) && sponsorFee0 != 0) {
                    IERC20(token0).safeTransfer(sponsor, sponsorFee0);
                }
            }
            if (token1 != WETH && amount1 - mgmtFee1 - sponsorFee1 > 0) {
                IERC20(token1).safeTransfer(userToDecrease, amount1 - mgmtFee1 - sponsorFee1);
                userElementOwner.token1Balance += mgmtFee1;
                if (sponsor != address(0) && sponsorFee1 != 0) {
                    IERC20(token0).safeTransfer(sponsor, sponsorFee1);
                }
            }
        }

        emit RemovedLiquidity(amount0, amount1, liquidity, userToDecrease);
    }

    /// function for handling the collect
    /// @dev collects from a public address, can be called by anyone - used to collect fees
    /// @return amount0 the amount how much token0 we got as fees
    /// @return amount1 the amount how much token1 we got as fees
    function publicCollect() external nonReentrant returns
    (
        uint256 amount0,
        uint256 amount1
    )
    {
        (amount0, amount1) = collect(0, 0);
    }

    /// function for handling the collect from the position manager contract
    /// @dev collects the accrued fees from the position manager contract and withdraws them to this contract
    /// @param decrease0 the amount how much token0 are currently in the contract after a decrease
    /// @param decrease0 the amount how much token1 are currently in the contract after a decrease
    /// @return amount0 the amount how much token0 we got as fees
    /// @return amount1 the amount how much token1 we got as fees
    function collect(uint decrease0, uint decrease1) internal returns
    (
        uint256 amount0,
        uint256 amount1
    )
    {
        // prepare collect params
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams(
            {
                tokenId : currentTokenId,
                recipient : address(this),
                amount0Max : type(uint128).max,
                amount1Max : type(uint128).max
            }
        );

        (amount0, amount1) = positionManager.collect(collectParams);

        // we need to account the tokens and then account fees
        amount0 -= decrease0;
        amount1 -= decrease1;

        positionManager.unwrapWETH9(0, address(this));

        // convert weth9
        IWETH9(WETH).approve(WETH, 0);
        IWETH9(WETH).approve(WETH, IERC20(WETH).balanceOf(address(this)));
        IWETH9(WETH).withdraw(IERC20(WETH).balanceOf(address(this)));

        // sweep the remaining tokens
        if (token0 != WETH) {
            positionManager.sweepToken(token0, 0, address(this));
        }
        if (token1 != WETH) {
            positionManager.sweepToken(token1, 0, address(this));
        }

        // get owner
        UserInfo storage ownerUserElement = userMapping[owner];

        require(totalLiquidity != 0, "totalLiquidity divisor is zero");

        // check for every user and allocate fee rewards
        uint userListLength = userList.length;
        for (uint i = 0; i < userListLength; i++) {
            UserInfo storage userElement = userMapping[userList[i]];

            // only if grace period is over we account
            if (userElement.earnTimestamp <= block.timestamp) {
                uint share0 = amount0 * userElement.liquidity / totalLiquidity;
                uint share1 = amount1 * userElement.liquidity / totalLiquidity;

                userElement.token0Balance += share0;
                userElement.token1Balance += share1;
            }
            else {
                uint share0 = amount0 * userElement.liquidity / totalLiquidity;
                uint share1 = amount1 * userElement.liquidity / totalLiquidity;

                ownerUserElement.token0Balance += share0;
                ownerUserElement.token1Balance += share1;
            }
        }
    }

    /// function to collect the accrued fees
    /// @dev used to collect the earned fees from the contract (as a user)
    function userCollect() external nonReentrant {
        // get user
        UserInfo storage userElement = userMapping[msg.sender];
        uint token0Balance = userElement.token0Balance;
        uint token1Balance = userElement.token1Balance;

        uint lefOverToken0Balance = userElement.leftOverToken0Balance;
        uint lefOverToken1Balance = userElement.leftOverToken1Balance;

        // check if no owner
        if (msg.sender != owner) {
            (, uint val2,,) = IYieldManager(yieldManager).getUserFactors(
                msg.sender,
                0
            );

            uint perfFee0 = (val2 * token0Balance) / 100 / 100;
            uint sPerfFee0;

            uint perfFee1 = (val2 * token1Balance) / 100 / 100;
            uint sPerfFee1;

            // sponsor lookup
            address sponsor = IYieldManager(yieldManager).getAffiliate(msg.sender);

            // get sponsor stats
            if (sponsor != address(0)) {
                (uint sval1,,,) = IYieldManager(yieldManager)
                    .getUserFactors(sponsor, 1);
                sPerfFee0 = (perfFee0 * sval1) / 100 / 100;
                perfFee0 -= sPerfFee0;
                sPerfFee1 = (perfFee1 * sval1) / 100 / 100;
                perfFee1 -= sPerfFee1;
            }

            // update user mapping
            UserInfo storage ownerElement = userMapping[owner];

            // send tokens
            if (token0 == WETH && (token0Balance - perfFee0 - sPerfFee0 > 0)) {
                payable(msg.sender).sendValue(token0Balance - perfFee0 - sPerfFee0 + lefOverToken0Balance);
                ownerElement.token0Balance += perfFee0;

                if (sponsor != address(0) && sPerfFee0 != 0) {
                    payable(sponsor).sendValue(sPerfFee0);
                }
            }
            if (token1 == WETH && (token1Balance - perfFee1 - sPerfFee1 > 0)) {
                payable(msg.sender).sendValue(token1Balance - perfFee1 - sPerfFee1 + lefOverToken1Balance);
                ownerElement.token1Balance += perfFee1;

                if (sponsor != address(0) && sPerfFee1 != 0) {
                    payable(sponsor).sendValue(sPerfFee1);
                }
            }
            if (token0 != WETH && token0Balance - perfFee0 - sPerfFee0 > 0) {
                IERC20(token0).safeTransfer(msg.sender, token0Balance - perfFee0 - sPerfFee0 + lefOverToken0Balance);
                ownerElement.token0Balance += perfFee0;

                if (sponsor != address(0) && sPerfFee0 != 0) {
                    IERC20(token0).safeTransfer(sponsor, sPerfFee0);
                }
            }
            if (token1 != WETH && token1Balance - perfFee1 - sPerfFee1 > 0) {
                IERC20(token1).safeTransfer(msg.sender, token1Balance - perfFee1 - sPerfFee1 + lefOverToken1Balance);
                ownerElement.token1Balance += perfFee1;

                if (sponsor != address(0) && sPerfFee1 != 0) {
                    IERC20(token1).safeTransfer(sponsor, sPerfFee1);
                }
            }
        }
            // user is owner
        else {
            // send tokens
            if (token0 == WETH && (token0Balance > 0)) {
                payable(feeReceiver).sendValue(token0Balance + lefOverToken0Balance);
            }
            if (token1 == WETH && (token1Balance > 0)) {
                payable(feeReceiver).sendValue(token1Balance + lefOverToken1Balance);
            }
            if (token0 != WETH && token0Balance > 0) {
                IERC20(token0).safeTransfer(feeReceiver, token0Balance + lefOverToken0Balance);

            }
            if (token1 != WETH && token1Balance > 0) {
                IERC20(token1).safeTransfer(feeReceiver, token1Balance + lefOverToken1Balance);
            }
        }

        // set fees to 0 since withdrawn
        userElement.token0Balance = 0;
        userElement.token1Balance = 0;

        userElement.leftOverToken0Balance = 0;
        userElement.leftOverToken1Balance = 0;

        emit FeesWithdrawn(token0Balance, token1Balance, msg.sender);
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     */
    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address for newOwner");

        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwner() external {
        require(_pendingOwner == msg.sender, "Unauthorized Account");
        owner = _pendingOwner;
        delete _pendingOwner;
        emit NewOwner(owner);
    }

    /**
     * @dev Starts the fee receiver transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     */
    function changeFeeReceiver(address newFeeReceiver) external {
        require(newFeeReceiver != address(0), "Zero address for newFeeReceiver");
        require(msg.sender == feeReceiver, "not fee receiver");

        _pendingFeeReceiver = newFeeReceiver;
        emit FeeReceiverTransferStarted(feeReceiver, newFeeReceiver);
    }

    /**
    * @dev The new fee receiver accepts the fee receiver transfer.
     */
    function acceptFeeReceiver() external {
        require(_pendingFeeReceiver == msg.sender, "Unauthorized Account");
        feeReceiver = _pendingFeeReceiver;
        delete _pendingFeeReceiver;
        emit NewFeeReceiver(owner);
    }

    /// sets multiple values
    /// @dev used to set various config values
    /// @param _newPositionManager the new value for _newPositionManager
    /// @param _newQuoter the new value for uniswapQuoter
    function changePositionParameter(address _newPositionManager, address _newQuoter) external onlyOwner nonReentrant {
        require(_newPositionManager != address(0), "Zero address for _newPositionManager");
        require(_newQuoter != address(0), "Zero address for _newQuoter");

        positionManager = INonfungiblePositionManager(_newPositionManager);
        uniswapV3Factory = IUniswapV3Factory(positionManager.factory());
        uniswapQuoter = IQuoter(_newQuoter);
    }

    /// sets the new yield manager
    /// @dev sets the value of the yield manager
    /// @param _newYieldManager the new value for _newYieldManager
    function changeYieldManager(address _newYieldManager) external onlyOwner {
        require(_newYieldManager != address(0), "Zero address for _newYieldManager");

        yieldManager = _newYieldManager;
        emit NewYieldManager(yieldManager);
    }

    /// sets the tick tickMoveThreshold
    /// @dev sets the value of the tickMoveThreshold
    /// @param _tickMoveThreshold the new value for _tickMoveThreshold
    function setTickMoveThreshold(int24 _tickMoveThreshold) external onlyOwner {
        require(_tickMoveThreshold <= 10000, "_tickMoveThreshold too big");
        tickMoveThreshold = _tickMoveThreshold;
        emit NewTickMoveThreshold(tickMoveThreshold);
    }

    /// sets the locked value
    /// @dev sets the value of isLocked and controls minting and increasing liquidity
    /// @param _locked the new value for _locked
    function setLocked(bool _locked) external onlyOwner {
        isLocked = _locked;
        emit Locked(_locked);
    }

    /// sets the earnCooldownPeriod value
    /// @dev sets the value of earnCooldownPeriod
    /// @param _earnCooldownPeriod the new value for earnCooldownPeriod
    function setEarnCooldownPeriod(uint _earnCooldownPeriod) external onlyOwner {
        // cap at 48h (60 * 60 * 48)
        require(_earnCooldownPeriod <= 172800, "_earnCooldownPeriod can be maximum 48h");

        earnCooldownPeriod = _earnCooldownPeriod;
        emit NewEarnCoolDownPeriod(_earnCooldownPeriod);
    }

    /// sets the checkMoveRangeDisabled value
    /// @dev sets the value of _checkMoveRangeDisabled and controls moving the range
    /// @param _checkMoveRangeDisabled the new value for _checkMoveRangeDisabled
    function setCheckMoveRangeDisabled(bool _checkMoveRangeDisabled) external onlyOwner {
        checkMoveRangeDisabled = _checkMoveRangeDisabled;
        emit CheckMoveRangeDisabled(_checkMoveRangeDisabled);
    }

    /// sets the move range addresses
    /// @dev sets the value of the addresses which can move the range
    /// @param moveAddress the address to be updated
    /// @param allowed the bool to set
    function setMoveRangeAddress(address moveAddress, bool allowed) external onlyOwner {
        moveRangeAddresses[moveAddress] = allowed;
        emit MoveAddressUpdated(moveAddress, allowed);
    }

    /// sets the newMaxUsers value
    /// @dev sets the value of maxUsers
    /// @param newMaxUsers the new value for newMaxUsers
    function setMaxUsers(uint newMaxUsers) external onlyOwner {
        maxUsers = newMaxUsers;
        emit NewMaxUsers(newMaxUsers);
    }

    // default fallback and receive functions
    fallback() external payable {}
    receive() external payable {}
}

// interface for the YieldManager
interface IYieldManager {

    /// Sets the wanted affiliate
    /// @dev sets the value of the sponsor variable at a client object
    /// @param client the mapping entry point
    /// @param sponsor the address to set as a sponsor
    function setAffiliate(address client, address sponsor) external;

    /// Gets the factors for user and sponsor
    /// @dev returns the client and sponsor factors
    /// @param user the client to look up
    /// @param typer the type (sponsor or client mode)
    function getUserFactors(
        address user,
        uint typer
    ) external view returns (uint, uint, uint, uint);

    /// Gets the wanted affiliate
    /// @dev gets the value of the sponsor variable at a client object
    /// @param client the mapping entry point
    function getAffiliate(address client) external view returns (address);
}

