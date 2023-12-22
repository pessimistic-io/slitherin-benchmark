// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {TickMath} from "./TickMath.sol";
import {FullMath, LiquidityAmounts} from "./LiquidityAmounts.sol";
import "./ReentrancyGuard.sol";
import {IUniswapV3Pool} from "./IUniswapV3Pool.sol";
pragma abicoder v2;
import "./TransferHelper.sol";
import "./ISwapRouter.sol";

interface IUniswapV3Factory {
    function owner() external view returns (address);

    function feeAmountTickSpacing(uint24 fee) external view returns (int24);

    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);

    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
    function setOwner(address _owner) external;
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
}

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function approve(address spender, uint value) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function withdraw(uint256) external;
}

interface IFACTORY {
    function enableFeeAmount(uint24 fee, int24 tickSpacing) external returns (bool);
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
}

interface IMinimalNonfungiblePositionManager {
    function createAndInitializePoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 sqrtPriceX96
    ) external payable returns (address pool);
    function positions(
        uint256 tokenId
    )
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;

    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    function increaseLiquidity(
        IncreaseLiquidityParams calldata params
    ) external payable returns (uint128 liquidity, uint256 amount0, uint256 amount1);
    function decreaseLiquidity(
        DecreaseLiquidityParams calldata params
    ) external payable returns (uint256 amount0, uint256 amount1);

    function mint(
        MintParams calldata params
    ) external returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    function burn(uint256 tokenId) external;

    /// @notice Collects up to a maximum amount of fees owed to a specific position to the recipient
    /// @param params tokenId The ID of the NFT for which tokens are being collected,
    /// recipient The account that should receive the tokens,
    /// amount0Max The maximum amount of token0 to collect,
    /// amount1Max The maximum amount of token1 to collect
    /// @return amount0 The amount of fees collected in token0
    /// @return amount1 The amount of fees collected in token1
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);
}

interface IFren {
    function balanceOf(address) external view returns (uint256);
    function approve(address spender, uint value) external returns (bool);
    function enableTrading() external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function initialize(uint160 sqrtPriceX96) external;
}

interface IGameContract {
    function applyHeal(address player) external;
    function applyProtect(address player) external;
}

contract MagicInternetCauldron is ReentrancyGuard {
    IMinimalNonfungiblePositionManager public positionManager;

    struct StakedPosition {
        uint256 tokenId;
        uint128 liquidity;
        uint256 stakedAt;
        uint256 lastRewardTime;
    }

    IUniswapV3Pool public pool;
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address public constant WETH_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; //BASE
    address public POSITION_MANAGER_ADDRESS = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88; // BASE
    mapping(address => bool) public isAuth;
    mapping(uint256 => address) public positionOwner;
    mapping(address => uint256) public frenReward;

    mapping(address => StakedPosition) public stakedPositions;
    address public MIMANA_ADDRESS;
    address public MIFREN_ADDRESS;

    int24 public tickSpacing = 200; // spacing of the miMana/ETH pool
    uint256 public SQRT_70_PERCENT = 836660026534075547; //
    uint256 public SQRT_130_PERCENT = 1140175425099137979; //
    bool printerBrrr = false;
    uint256[] public stakedTokenIds;
    address public owner;
    int24 MinTick = -887200; // Replace with actual min tick for the pool
    int24 MaxTick = 887200; // Replace with actual max tick for the pool
    uint128 public totalStakedLiquidity;
    uint256 public dailyRewardAmount = 1 * 10 ** 18; // Daily reward amount in miMana tokens
    uint256 public initRewardTime;
    uint256 public constant HEAL_POTION_COST = 100;
    uint256 public constant PROTECT_POTION_COST = 200;
    IGameContract public gameContract;

    event PositionDeposited(uint256 indexed tokenId, address indexed from, address indexed to);

    constructor(address miFren, address miMana) {
        owner = msg.sender;
        isAuth[owner] = true;
        isAuth[address(this)] = true;
        MIMANA_ADDRESS = miMana;
        MIFREN_ADDRESS = miFren;
        positionManager = IMinimalNonfungiblePositionManager(POSITION_MANAGER_ADDRESS); // Base UniV3 Position Manager
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the authorized");
        _;
    }
    // Modifier to restrict access to owner only
    modifier onlyAuth() {
        require(msg.sender == owner || isAuth[msg.sender], "Caller is not the authorized");
        _;
    }

    function setIsAuth(address fren, bool isAuthorized) external onlyAuth {
        isAuth[fren] = isAuthorized;
    }

    function setGameContract(address GameContract) public onlyOwner {
        gameContract = IGameContract(GameContract);
    }

    function setPool(address _pool) public onlyAuth {
        pool = IUniswapV3Pool(_pool);
    }

    function initRewards() public onlyAuth {
        initRewardTime = block.timestamp;
        printerBrrr = true;
    }

    function getPositionValue(
        uint256 tokenId
    ) public view returns (uint128 liquidity, address token0, address token1, int24 tickLower, int24 tickUpper) {
        (
            ,
            ,
            // nonce
            // operator
            address _token0, // token0
            address _token1, // token1 // fee
            ,
            int24 _tickLower, // tickLower
            int24 _tickUpper, // tickUpper
            uint128 _liquidity, // liquidity // feeGrowthInside0LastX128 // feeGrowthInside1LastX128 // tokensOwed0 // tokensOwed1
            ,
            ,
            ,

        ) = positionManager.positions(tokenId);

        return (_liquidity, _token0, _token1, _tickLower, _tickUpper);
    }

    function setDailyRewardAmount(uint256 _amount) external onlyOwner {
        dailyRewardAmount = _amount;
    }

    function stakePosition(uint256 tokenId) public nonReentrant {
        (uint128 liquidity, address token0, address token1, int24 tickLower, int24 tickUpper) = getPositionValue(
            tokenId
        );
        require(IFren(MIFREN_ADDRESS).balanceOf(msg.sender) > 0, "You need to own a Fren to stake");
        require(stakedPositions[msg.sender].tokenId == 0, "You Already have a staked position Fren");
        require(
            (token0 == MIMANA_ADDRESS && token1 == WETH_ADDRESS) ||
                (token0 == WETH_ADDRESS && token1 == MIMANA_ADDRESS),
            "Position does not involve the correct token pair"
        );
        require(liquidity > 0, "Invalid liquidity");
        require(tickLower == MinTick && tickUpper == MaxTick, "Position does not span full range");

        // Transfer the NFT to this contract for staking
        // Ensure the NFT contract supports safeTransferFrom and the sender is the NFT owner
        positionManager.safeTransferFrom(msg.sender, address(this), tokenId, "");

        positionOwner[tokenId] = msg.sender;
        stakedPositions[msg.sender] = StakedPosition(tokenId, liquidity, block.timestamp, block.timestamp);
        stakedTokenIds.push(tokenId); // Add the token ID to the array
        totalStakedLiquidity += liquidity;

        // Additional logic for reward calculation start
    }

    function withdrawPosition(uint256 tokenId) external nonReentrant {
        StakedPosition memory stakedPosition = stakedPositions[msg.sender];

        require(stakedPosition.tokenId == tokenId, "Not staked token");
        require(positionOwner[tokenId] == msg.sender, "Not position owner");

        // Transfer the NFT back to the user
        positionManager.safeTransferFrom(address(this), msg.sender, tokenId, "");

        totalStakedLiquidity -= stakedPosition.liquidity;
        // Clear the staked position data
        // Remove the tokenId from the stakedTokenIds array
        for (uint i = 0; i < stakedTokenIds.length; i++) {
            if (stakedTokenIds[i] == tokenId) {
                stakedTokenIds[i] = stakedTokenIds[stakedTokenIds.length - 1];
                stakedTokenIds.pop();
                break;
            }
        }
        delete positionOwner[tokenId];
        delete stakedPositions[msg.sender];
        removeTokenIdFromArray(tokenId);
    }

    function pendingInflactionaryRewards(address user) public view returns (uint256 rewards) {
        StakedPosition memory position = stakedPositions[user];

        if (position.liquidity == 0 || calculateSumOfLiquidity() == 0 || !printerBrrr) {
            return 0;
        }
        uint128 userLiq = position.liquidity;
        uint128 totalLiq = calculateSumOfLiquidity();
        uint256 _timeElapsed;
        if (position.lastRewardTime < initRewardTime) {
            _timeElapsed = block.timestamp - initRewardTime;
        } else {
            _timeElapsed = block.timestamp - position.lastRewardTime;
        }

        uint128 userShare = div64x64(userLiq, totalLiq);

        rewards = (dailyRewardAmount * _timeElapsed * userShare) / 1e18;
    }

    function pendingRewards(address user) public view returns (uint256 rewards) {
        rewards = frenReward[user] + pendingInflactionaryRewards(user);
    }

    function div64x64(uint128 x, uint128 y) internal pure returns (uint128) {
        unchecked {
            require(y != 0);

            uint256 answer = (uint256(x) << 64) / y;

            require(answer <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
            return uint128(answer);
        }
    }

    function claimRewards() public nonReentrant {
        StakedPosition storage position = stakedPositions[msg.sender];
        require(isCauldronInRange(msg.sender), "Rebalance the fire in your Cauldron");

        // Add pending inflationary rewards to rewards
        uint256 rewards = pendingInflactionaryRewards(msg.sender) + frenReward[msg.sender];

        require(rewards > 0, "No rewards available");

        // Set frenReward[msg.sender] to zero
        frenReward[msg.sender] = 0;

        position.lastRewardTime = block.timestamp; // Update the last reward time

        // Transfer miMana tokens to the user
        // Ensure that the contract has enough miMana tokens and is authorized to distribute them
        require(IFren(MIMANA_ADDRESS).balanceOf(address(this)) >= rewards, "No more $miMana to give");

        IFren(MIMANA_ADDRESS).transfer(msg.sender, rewards);

        // Emit an event if necessary
        // emit RewardsClaimed(msg.sender, rewards);
    }

    function claimRewardsAuth(address fren, uint256 itemPrice) public onlyAuth nonReentrant {
        StakedPosition storage position = stakedPositions[fren];
        require(isCauldronInRange(fren), "Rebalance the fire in your Cauldron");

        // Add pending inflationary rewards to rewards
        uint256 rewards = pendingInflactionaryRewards(fren) + frenReward[fren] - itemPrice;

        require(rewards > 0, "No rewards available");

        // Set frenReward[msg.sender] to zero
        frenReward[fren] = 0;

        position.lastRewardTime = block.timestamp; // Update the last reward time

        // Transfer miMana tokens to the user
        // Ensure that the contract has enough miMana tokens and is authorized to distribute them
        require(IFren(MIMANA_ADDRESS).balanceOf(address(this)) >= rewards, "No more $miMana to give");

        IFren(MIMANA_ADDRESS).transfer(fren, rewards);

        // Emit an event if necessary
        // emit RewardsClaimed(msg.sender, rewards);
    }

    function drinkHealPotion() public nonReentrant {
        consumePotion(HEAL_POTION_COST);
    }

    function drinkProtectPotion() public nonReentrant {
        consumePotion(PROTECT_POTION_COST);
    }

    function consumePotion(uint256 potionCost) private {
        StakedPosition storage position = stakedPositions[msg.sender];
        require(position.tokenId != 0, "No staked position");
        uint256 rewards;
        if (printerBrrr) {
            rewards = pendingInflactionaryRewards(msg.sender);
        } else {
            rewards = pendingRewards(msg.sender);
        }

        require(rewards >= potionCost, "Insufficient rewards to drink potion");

        position.lastRewardTime = block.timestamp; // Update the last reward time

        uint256 remainingRewards = rewards - potionCost;
        // Transfer remaining rewards to the user
        // miManaToken.transfer(msg.sender, remainingRewards);
        require(IFren(MIMANA_ADDRESS).balanceOf(address(this)) > remainingRewards, "No more $miMana to give");

        IFren(MIMANA_ADDRESS).transfer(msg.sender, remainingRewards);
        // Emit an event for drinking the potion
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes memory) public virtual returns (bytes4) {
        emit PositionDeposited(tokenId, from, address(this));
        return this.onERC721Received.selector;
    }

    function collectAllFees() external returns (uint256 totalAmount0, uint256 totalAmount1) {
        uint256 amount0;
        uint256 amount1;

        for (uint i = 0; i < stakedTokenIds.length; i++) {
            IMinimalNonfungiblePositionManager.CollectParams memory params = IMinimalNonfungiblePositionManager
                .CollectParams({
                    tokenId: stakedTokenIds[i],
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                });

            (amount0, amount1) = positionManager.collect(params);
            totalAmount0 += amount0;
            totalAmount1 += amount1;
        }
    }

    function frensFundus() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{value: address(this).balance}("");
        require(success);
    }

    function somethingAboutTokens(address token) external onlyOwner {
        uint256 balance = IFren(token).balanceOf(address(this));
        IFren(token).transfer(msg.sender, balance);
    }

    function swapWETH(uint value) public payable returns (uint amountOut) {
        // Approve the router to spend WETH
        IWETH(WETH_ADDRESS).approve(address(swapRouter), value);

        // Set up swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH_ADDRESS,
            tokenOut: MIMANA_ADDRESS,
            fee: 10000, // Assuming a 0.1% pool fee
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: value,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // Perform the swap
        amountOut = swapRouter.exactInputSingle(params);
    }

    function swapETH_Half(uint value, bool isWETH) public payable returns (uint amountOut) {
        if (!isWETH) {
            // Wrap ETH to WETH
            IWETH(WETH_ADDRESS).deposit{value: value}();
            assert(IWETH(WETH_ADDRESS).transfer(address(this), value));
        }

        uint amountToSwap = value / 2;

        // Approve the router to spend WETH
        IWETH(WETH_ADDRESS).approve(address(swapRouter), value);

        // Set up swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH_ADDRESS,
            tokenOut: MIMANA_ADDRESS,
            fee: 10000, // Assuming a 0.1% pool fee
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountToSwap,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // Perform the swap
        amountOut = swapRouter.exactInputSingle(params);
    }

    function brewManaFromETH()
        public
        payable
        returns (uint _tokenId, uint128 liquidity, uint amount0, uint amount1, uint refund0, uint refund1)
    {
        require(msg.value > 0, "Must send ETH to the Cauldron");

        uint amountMana = swapETH_Half(msg.value, false);

        uint amountWETH = IWETH(WETH_ADDRESS).balanceOf(address(this));

        // For this example, we will provide equal amounts of liquidity in both assets.
        // Providing liquidity in both assets means liquidity will be earning fees and is considered in-range.
        uint amount0ToMint = amountMana;
        uint amount1ToMint = amountWETH;

        // Approve the position manager
        TransferHelper.safeApprove(MIMANA_ADDRESS, address(POSITION_MANAGER_ADDRESS), amount0ToMint);
        TransferHelper.safeApprove(WETH_ADDRESS, address(POSITION_MANAGER_ADDRESS), amount1ToMint);

        if (stakedPositions[msg.sender].tokenId != 0) {
            // User already has a staked position, call function to increase liquidity
            return increasePosition(msg.sender, amountMana, amountWETH);
        } else {
            // User does not have a staked position, proceed with minting a new one
            return mintPosition(msg.sender, msg.sender, amountMana, amountWETH);
        }
    }

    function brewManaFromMANA_ETH(
        uint _amountMana
    )
        public
        payable
        returns (uint _tokenId, uint128 liquidity, uint amount0, uint amount1, uint refund0, uint refund1)
    {
        require(msg.value > 0, "Must send ETH to the Cauldron");

        // Wrap ETH to WETH
        IWETH(WETH_ADDRESS).deposit{value: msg.value}();
        assert(IWETH(WETH_ADDRESS).transfer(address(this), msg.value));

        uint amountWETH = IWETH(WETH_ADDRESS).balanceOf(address(this));
        IFren(MIMANA_ADDRESS).transferFrom(msg.sender, address(this), _amountMana);
        // For this example, we will provide equal amounts of liquidity in both assets.
        // Providing liquidity in both assets means liquidity will be earning fees and is considered in-range.
        uint amount0ToMint = _amountMana;
        uint amount1ToMint = msg.value;

        // Approve the position manager
        TransferHelper.safeApprove(MIMANA_ADDRESS, address(POSITION_MANAGER_ADDRESS), amount0ToMint);
        TransferHelper.safeApprove(WETH_ADDRESS, address(POSITION_MANAGER_ADDRESS), amount1ToMint);

        if (stakedPositions[msg.sender].tokenId != 0) {
            // User already has a staked position, call function to increase liquidity
            return increasePosition(msg.sender, _amountMana, amountWETH);
        } else {
            // User does not have a staked position, proceed with minting a new one
            return mintPosition(msg.sender, msg.sender, _amountMana, amountWETH);
        }
    }

    function isCauldronInRange(address fren) public view returns (bool) {
        int24 tick = getCurrentTick();
        StakedPosition memory position = stakedPositions[fren];
        (, , , int24 minTick, int24 maxTick) = getPositionValue(position.tokenId);

        if (minTick < tick && tick < maxTick) {
            return true;
        } else {
            return false;
        }
    }

    function getCurrentTick() public view returns (int24) {
        (, int24 tick, , , , , ) = pool.slot0();
        return tick;
    }

    function swapMana_Half(uint value) public payable returns (uint amountOut) {
        uint amountToSwap = value / 2;

        // Approve the router to spend WETH
        IFren(MIMANA_ADDRESS).approve(address(swapRouter), value);

        // Set up swap parameters
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: MIMANA_ADDRESS,
            tokenOut: WETH_ADDRESS,
            fee: 10000, // Assuming a 0.3% pool fee
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountToSwap,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // Perform the swap
        amountOut = swapRouter.exactInputSingle(params);
    }

    function mintCauldron(
        address fren,
        address rafundAddress,
        uint _amountMana,
        uint _amountWETH
    ) external returns (uint _tokenId, uint128 liquidity, uint amount0, uint amount1, uint refund1, uint refund0) {
        return mintPosition(fren, rafundAddress, _amountMana, _amountWETH);
    }

    function mintPosition(
        address fren,
        address rafundAddress,
        uint _amountMana,
        uint _amountWETH
    ) internal returns (uint _tokenId, uint128 liquidity, uint amount0, uint amount1, uint refund1, uint refund0) {
        uint256 _deadline = block.timestamp + 3360;
        (int24 lowerTick, int24 upperTick) = _getSpreadTicks();
        IMinimalNonfungiblePositionManager.MintParams memory params = IMinimalNonfungiblePositionManager.MintParams({
            token0: MIMANA_ADDRESS,
            token1: WETH_ADDRESS,
            fee: 10000,
            // By using TickMath.MIN_TICK and TickMath.MAX_TICK,
            // we are providing liquidity across the whole range of the pool.
            // Not recommended in production.
            tickLower: lowerTick,
            tickUpper: upperTick,
            amount0Desired: _amountMana,
            amount1Desired: _amountWETH,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: _deadline
        });

        // Note that the pool defined by miMana/WETH and fee tier 0.1% must
        // already be created and initialized in order to mint
        (_tokenId, liquidity, amount0, amount1) = positionManager.mint(params);
        positionOwner[_tokenId] = fren;

        stakedPositions[fren] = StakedPosition(_tokenId, liquidity, block.timestamp, block.timestamp);
        stakedTokenIds.push(_tokenId); // Add the token ID to the array
        totalStakedLiquidity += liquidity;

        if (amount0 < _amountMana) {
            refund0 = _amountMana - amount0;
            //TransferHelper.safeTransfer(MIMANA_ADDRESS, rafundAddress, refund0);
            frenReward[rafundAddress] += refund0;
        }

        if (amount1 < _amountWETH) {
            refund1 = _amountWETH - amount1;
            TransferHelper.safeTransfer(WETH_ADDRESS, rafundAddress, refund1);
            // uint256 amountMana = swapWETH(refund1);
            //TransferHelper.safeTransfer(MIMANA_ADDRESS, rafundAddress, amountMana);
            //frenReward[rafundAddress] += amountMana;
        }
    }

    function rebalancePosition(address fren) public returns (uint _refund0, uint _refund1) {
        return _rebalancePosition(fren, fren);
    }

    function _rebalancePosition(address fren, address refund) public returns (uint _refund0, uint _refund1) {
        // require(msg.sender == owner || isAuth[msg.sender] || fren == tx.origin, "Caller is not the authorized");
        if (!isCauldronInRange(fren)) {
            StakedPosition storage position = stakedPositions[fren];
            uint256 oldTokenID = position.tokenId;
            int24 currentTick = getCurrentTick();
            (, , , int24 minTick, int24 maxTick) = getPositionValue(position.tokenId);

            // Determine if the current price is above or below the range
            if (currentTick > maxTick) {
                // Decrease the entire position, assuming all liquidity is in WETH

                // Swap half of the WETH to another asset and then mint a new position
                uint amountWETHBeforeSwap = IWETH(WETH_ADDRESS).balanceOf(address(this));
                (, uint amountWeth) = _decreaseLiquidity(position.liquidity, fren, address(this));

                uint _amountMana = swapETH_Half(amountWeth, true);
                uint amountWETHAfterSwap = IWETH(WETH_ADDRESS).balanceOf(address(this));
                uint amountWethADD = amountWETHAfterSwap - amountWETHBeforeSwap;

                TransferHelper.safeApprove(MIMANA_ADDRESS, address(POSITION_MANAGER_ADDRESS), _amountMana);
                TransferHelper.safeApprove(WETH_ADDRESS, address(POSITION_MANAGER_ADDRESS), amountWethADD);
                (, , , , _refund0, _refund1) = mintPosition(fren, refund, _amountMana, amountWethADD);
            } else if (currentTick < minTick) {
                uint amountManaBeforeSwap = IWETH(WETH_ADDRESS).balanceOf(address(this));
                (uint amountMana, ) = _decreaseLiquidity(position.liquidity, fren, address(this));

                uint _amountWeth = swapMana_Half(amountMana);
                uint amountManaAfterSwap = IWETH(WETH_ADDRESS).balanceOf(address(this));
                uint amountManaADD = amountManaAfterSwap - amountManaBeforeSwap;

                TransferHelper.safeApprove(MIMANA_ADDRESS, address(POSITION_MANAGER_ADDRESS), amountManaADD);
                TransferHelper.safeApprove(WETH_ADDRESS, address(POSITION_MANAGER_ADDRESS), _amountWeth);
                (, , , , _refund0, _refund1) = mintPosition(fren, refund, amountManaADD, _amountWeth);
            }
        }
    }

    function calculateSumOfLiquidity() public view returns (uint128) {
        uint128 totalLiq = 0;

        for (uint256 i = 0; i < stakedTokenIds.length; i++) {
            uint256 tokenId = stakedTokenIds[i];
            address fren = positionOwner[tokenId];

            // Check if the position owner satisfies the condition
            if (isCauldronInRange(fren)) {
                StakedPosition storage position = stakedPositions[fren];

                // Add up the liquidity
                totalLiq += position.liquidity;
            }
        }

        return totalLiq;
    }

    function increasePosition(
        address fren,
        uint _amountMana,
        uint _amountWETH
    ) internal returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1, uint refund0, uint refund1) {
        tokenId = stakedPositions[fren].tokenId;

        uint256 _deadline = block.timestamp + 100;
        IMinimalNonfungiblePositionManager.IncreaseLiquidityParams memory params = IMinimalNonfungiblePositionManager
            .IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: _amountMana,
                amount1Desired: _amountWETH,
                amount0Min: 0,
                amount1Min: 0,
                deadline: _deadline
            });

        (liquidity, amount0, amount1) = positionManager.increaseLiquidity(params);
        uint128 curr_liquidity = stakedPositions[msg.sender].liquidity + liquidity;

        stakedPositions[msg.sender] = StakedPosition(tokenId, curr_liquidity, block.timestamp, block.timestamp);
        stakedTokenIds.push(tokenId); // Add the token ID to the array
        totalStakedLiquidity += liquidity;

        if (amount0 < _amountMana) {
            refund0 = _amountMana - amount0;
            TransferHelper.safeTransfer(MIMANA_ADDRESS, fren, refund0);
        }

        if (amount1 < _amountWETH) {
            refund1 = _amountWETH - amount1;
            TransferHelper.safeTransfer(WETH_ADDRESS, fren, refund1);
        }
    }

    function removeTokenIdFromArray(uint256 tokenId) internal {
        uint256 length = stakedTokenIds.length;
        for (uint256 i = 0; i < length; i++) {
            if (stakedTokenIds[i] == tokenId) {
                // Swap with the last element
                stakedTokenIds[i] = stakedTokenIds[length - 1];
                // Remove the last element
                stakedTokenIds.pop();
                break;
            }
        }
    }

    function _getStakedPositionID(address fren) public view returns (uint256 tokenId) {
        StakedPosition memory position = stakedPositions[fren];
        return position.tokenId;
    }

    function _getSpreadTicks() public view returns (int24 _lowerTick, int24 _upperTick) {
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        (uint160 sqrtRatioAX96, uint160 sqrtRatioBX96) = (
            uint160(FullMath.mulDiv(sqrtPriceX96, SQRT_70_PERCENT, 1e18)),
            uint160(FullMath.mulDiv(sqrtPriceX96, SQRT_130_PERCENT, 1e18))
        );

        _lowerTick = TickMath.getTickAtSqrtRatio(sqrtRatioAX96);
        _upperTick = TickMath.getTickAtSqrtRatio(sqrtRatioBX96);

        _lowerTick = _lowerTick % tickSpacing == 0
            ? _lowerTick // accept valid tickSpacing
            : _lowerTick > 0 // else, round up to closest valid tickSpacing
            ? (_lowerTick / tickSpacing + 1) * tickSpacing
            : (_lowerTick / tickSpacing) * tickSpacing;
        _upperTick = _upperTick % tickSpacing == 0
            ? _upperTick // accept valid tickSpacing
            : _upperTick > 0 // else, round down to closest valid tickSpacing
            ? (_upperTick / tickSpacing) * tickSpacing
            : (_upperTick / tickSpacing - 1) * tickSpacing;
    }

    function decreaseLiquidity(uint128 liquidity, address fren) public returns (uint amount0, uint amount1) {
        return _decreaseLiquidity(liquidity, fren, fren);
    }

    function _decreaseLiquidity(
        uint128 liquidity,
        address fren,
        address receiver
    ) internal returns (uint amount0, uint amount1) {
        //require(msg.sender == owner || isAuth[msg.sender] || tx.origin == fren, "Caller is not the authorized");
        require(stakedPositions[fren].tokenId != 0, "No positions in Cauldron");
        uint256 tokenId = stakedPositions[fren].tokenId;
        uint128 currentLiquidity = stakedPositions[fren].liquidity;
        require(currentLiquidity >= liquidity, "Not Enough Liquidity in your Cauldron");
        uint128 newliq = currentLiquidity - liquidity;
        IMinimalNonfungiblePositionManager.DecreaseLiquidityParams memory params = IMinimalNonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });
        totalStakedLiquidity -= liquidity;
        uint amountManaBefore = IWETH(MIMANA_ADDRESS).balanceOf(address(this));
        uint amountWETHBefore = IWETH(WETH_ADDRESS).balanceOf(address(this));
        stakedPositions[fren] = StakedPosition(tokenId, newliq, block.timestamp, block.timestamp);
        (amount0, amount1) = positionManager.decreaseLiquidity(params);
        IMinimalNonfungiblePositionManager.CollectParams memory colectparams = IMinimalNonfungiblePositionManager
            .CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = positionManager.collect(colectparams);
        uint amountManaAfter = IWETH(MIMANA_ADDRESS).balanceOf(address(this));
        uint amountWETHAfter = IWETH(WETH_ADDRESS).balanceOf(address(this));
        uint refund0 = amountManaAfter - amountManaBefore;
        uint refund1 = amountWETHAfter - amountWETHBefore;

        if (refund0 > 0) {
            TransferHelper.safeTransfer(MIMANA_ADDRESS, receiver, refund0);
        }

        if (refund1 > 0) {
            //IERC20(WETH_ADDRESS).approve(address(this), refund1);
            //IWETH(WETH_ADDRESS).withdraw(refund1);
            //payable(receiver).transfer(refund1);
            TransferHelper.safeTransfer(WETH_ADDRESS, receiver, refund1);
        }

        if (newliq == 0) {
            positionManager.burn(stakedPositions[fren].tokenId);
            delete positionOwner[stakedPositions[fren].tokenId];
            removeTokenIdFromArray(stakedPositions[fren].tokenId);
            delete stakedPositions[fren];
        }
    }

    function _decreaseLiquidityExternal(
        uint128 liquidity,
        address fren,
        address receiver
    ) external returns (uint amount0, uint amount1) {
        require(msg.sender == owner || isAuth[msg.sender] || tx.origin == fren, "Caller is not the authorized");
        require(stakedPositions[fren].tokenId != 0, "No positions in Cauldron");
        uint256 tokenId = stakedPositions[fren].tokenId;
        uint128 currentLiquidity = stakedPositions[fren].liquidity;
        require(currentLiquidity >= liquidity, "Not Enough Liquidity in your Cauldron");
        uint128 newliq = currentLiquidity - liquidity;
        IMinimalNonfungiblePositionManager.DecreaseLiquidityParams memory params = IMinimalNonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });
        totalStakedLiquidity -= liquidity;
        uint amountManaBefore = IWETH(MIMANA_ADDRESS).balanceOf(address(this));
        uint amountWETHBefore = IWETH(WETH_ADDRESS).balanceOf(address(this));
        stakedPositions[fren] = StakedPosition(tokenId, newliq, block.timestamp, block.timestamp);
        (amount0, amount1) = positionManager.decreaseLiquidity(params);
        IMinimalNonfungiblePositionManager.CollectParams memory colectparams = IMinimalNonfungiblePositionManager
            .CollectParams({
                tokenId: tokenId,
                recipient: address(this),
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            });

        (amount0, amount1) = positionManager.collect(colectparams);
        uint amountManaAfter = IWETH(MIMANA_ADDRESS).balanceOf(address(this));
        uint amountWETHAfter = IWETH(WETH_ADDRESS).balanceOf(address(this));
        uint refund0 = amountManaAfter - amountManaBefore;
        uint refund1 = amountWETHAfter - amountWETHBefore;

        if (refund0 > 0) {
            TransferHelper.safeTransfer(MIMANA_ADDRESS, receiver, refund0);
        }

        if (refund1 > 0) {
            //IERC20(WETH_ADDRESS).approve(address(this), refund1);
            //IWETH(WETH_ADDRESS).withdraw(refund1);
            //payable(receiver).transfer(refund1);
            TransferHelper.safeTransfer(WETH_ADDRESS, receiver, refund1);
        }

        if (newliq == 0) {
            positionManager.burn(stakedPositions[fren].tokenId);
            delete positionOwner[stakedPositions[fren].tokenId];
            removeTokenIdFromArray(stakedPositions[fren].tokenId);
            delete stakedPositions[fren];
        }
    }

    function setTicks(int24 _minTick, int24 _maxTick, int24 _tickSpacing) public onlyOwner {
        MaxTick = _maxTick;
        MinTick = _minTick;
        tickSpacing = _tickSpacing;
    }
}

