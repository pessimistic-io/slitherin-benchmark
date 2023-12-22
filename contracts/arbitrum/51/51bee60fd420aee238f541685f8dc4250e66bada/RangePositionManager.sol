// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./INonfungiblePositionManager.sol";
import "./SafeERC20.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";

contract RangePositionManager {
    using SafeERC20 for IERC20;

    uint256 public currentTokenId;
    uint128 public totalLiquidity;

    uint256 public totalAmount0;
    uint256 public totalAmount1;

    int24 internal currentTickLower;
    int24 internal currentTickUpper;

    address internal WETH;
    address internal token0;
    address internal token1;
    uint24 internal fee;
    int24 public tickRangeThreshold; // Maximum acceptable price deviation threshold in basis points (1 basis point = 0.01%, 50 basis points = 0.5%, 100 basis points = 1%)
    int24 public tickMoveThreshold; // Maximum acceptable price deviation threshold in basis points (1 basis point = 0.01%, 50 basis points = 0.5%, 100 basis points = 1%)
    address yieldManager;

    address public owner;
    INonfungiblePositionManager public positionManager;
    IUniswapV3Pool internal uniswapV3Pool;
    IUniswapV3Factory internal uniswapV3Factory;

    address[] public userList;

    struct UserInfo {
        uint liquidity;
        uint earnTimestamp;
        uint token0Balance;
        uint token1Balance;
    }

    mapping (address => UserInfo) public userMapping;
    mapping (address => bool) internal isUser; // default `false`

    // only owner modifier
    modifier onlyOwner {
        _onlyOwner();
        _;
    }

    // only owner view
    function _onlyOwner() private view {
        require(msg.sender == owner || msg.sender == address(this), "Only the contract owner may perform this action");
    }

    event Mint(uint amount0, uint amount1, uint liquidity, uint tokenId, address user);
    event IncreaseLiquidity(uint amount0, uint amount1, uint liquidity, address user);
    event RemovedLiquidity(uint amount0, uint amount1, uint liquidity, address user);
    event FeesWithdrawn(uint amount0, uint amount1, address user);
    event NewTickDeviation(int24 tickDeviationThreshold);

    constructor(
        address _owner,
        address _positionManager,
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickRangeThreshold,
        int24 _tickMoveThreshold,
        address _yieldManager
    ){
        owner = _owner;
        token0 = _token0;
        token1 = _token1;
        fee = _fee;

        positionManager = INonfungiblePositionManager(_positionManager);
        uniswapV3Factory= IUniswapV3Factory(positionManager.factory());
        uniswapV3Pool = IUniswapV3Pool(uniswapV3Factory.getPool(token0, token1, fee));
        WETH = positionManager.WETH9();

        tickRangeThreshold = _tickRangeThreshold;
        tickMoveThreshold = _tickMoveThreshold;
        yieldManager = _yieldManager;
    }

    // owner function to create new and initial nft is also the setup method
    function mint(int24 tickLower, int24 tickUpper, uint amountDesired0, uint amountDesired1, uint slippagePercent) public payable onlyOwner {
        if (msg.sender == owner) {
            require (totalLiquidity == 0);
        }

        // get mint decreaseParams
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amountDesired0,
            amount1Desired: amountDesired1,
            amount0Min: amountDesired0 * slippagePercent / 10000,
            amount1Min: amountDesired1 * slippagePercent / 10000,
            recipient: address(this),
            deadline: block.timestamp
        });

        if (mintParams.token0 != WETH) {
            IERC20(mintParams.token0).safeApprove(address(positionManager),0);
            IERC20(mintParams.token0).safeApprove(address(positionManager),mintParams.amount0Desired);
        }

        if (mintParams.token1 != WETH) {
            IERC20(mintParams.token1).safeApprove(address(positionManager),0);
            IERC20(mintParams.token1).safeApprove(address(positionManager),mintParams.amount1Desired);
        }

        uint256 tokenId;
        uint256 amount0;
        uint256 amount1;
        uint128 liquidity;

        // adjustment
        if (msg.sender == address(this)) {
            (tokenId, liquidity, amount0, amount1) = positionManager.mint{value : token0 == WETH ? mintParams.amount0Desired : (token1 == WETH ? mintParams.amount1Desired : 0)}(mintParams);
            positionManager.refundETH();

            uint amount0Diff = amountDesired0 - amount0;
            uint amount1Diff = amountDesired1 - amount1;

            // update user percentages
            for (uint i=0; i <userList.length; i++) {
                UserInfo memory userElement = userMapping[userList[i]];
                userElement.liquidity = userElement.liquidity * liquidity / totalLiquidity;

                if(amountDesired0 > 0) {
                    userElement.token0Balance += amount0Diff * userElement.liquidity / liquidity;
                }
                if(amountDesired1 > 0) {
                    userElement.token1Balance += amount1Diff * userElement.liquidity / liquidity;
                }
            }
        }
        // sender is not the contract
        else {
            (tokenId, liquidity, amount0, amount1) = positionManager.mint{value : msg.value}(mintParams);
            positionManager.refundETH();

            if (token0 == WETH && (msg.value-amount0 > 0)) {
                payable(msg.sender).transfer(msg.value-amount0);
            }
            if (token1 == WETH && (msg.value-amount1 > 0)) {
                payable(msg.sender).transfer(msg.value-amount1 );
            }
            if (token0 != WETH && amountDesired0 - amount0 > 0) {
                IERC20(token0).safeTransfer(msg.sender, amountDesired0 - amount0);
            }
            if (token1 != WETH && amountDesired1 - amount1 > 0) {
                IERC20(token1).safeTransfer(msg.sender, amountDesired1 - amount1);
            }

            //add owner init as user
            if (isUser[msg.sender] == false) {
                // push the unique item to the array
                userList.push(msg.sender);
                isUser[msg.sender] = true;
            }
        }

        totalAmount0 = amount0;
        totalAmount1 = amount1;
        totalLiquidity = liquidity;
        currentTokenId = tokenId;
        currentTickUpper = tickUpper;
        currentTickLower = tickLower;

        emit Mint(amount0, amount1, liquidity, currentTokenId, msg.sender);
    }

    // view to check if moveRange can be called
    function canMoveRange() public view returns (bool) {
        //get the current tick
        (,int24 currentTick,,,,,) = uniswapV3Pool.slot0();
        int24 hardLimitTickUpper = currentTickUpper - (currentTickUpper * tickMoveThreshold / 10000);
        int24 hardLimitTickLower = currentTickLower + (currentTickLower * tickMoveThreshold / 10000);

        return currentTick > hardLimitTickUpper || currentTick < hardLimitTickLower;
    }

    // called to readjust the ranges (books out + mints new)
    function moveRange(uint slippagePercent) external onlyOwner {
        require(currentTokenId != 0, 'Not initialized');
        require(canMoveRange(), "Not allowed to move range");

        // collect fees
        collect();

        // decrease to 0
        (uint amount0, uint amount1) = decreaseLiquidity(totalAmount0, totalAmount1, slippagePercent, totalLiquidity);

        // mint new
        (,int24 currentTick,,,,,) = uniswapV3Pool.slot0();
        // Calculate the upper and lower tick bounds based on the current tick and the price deviation threshold
        int24 tickDeviation = currentTick * tickRangeThreshold / 10000;
        int24 newTickUpper = currentTick + tickDeviation;
        int24 newTickLower = currentTick - tickDeviation;

        mint(newTickLower, newTickUpper, amount0, amount1, slippagePercent);
    }

    // user function to add funds to the contract
    function increaseLiquidity(uint amountDesired0, uint amountDesired1, uint slippagePercent)
    external
    payable
    {
        // get increase params
        INonfungiblePositionManager.IncreaseLiquidityParams memory increaseParams = INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: currentTokenId,
            amount0Desired: amountDesired0,
            amount1Desired: amountDesired1,
            amount0Min: amountDesired0 * slippagePercent /10000,
            amount1Min: amountDesired1 * slippagePercent /10000,
            deadline: block.timestamp
        });

        if (token0 != WETH) {
            IERC20(token0).safeTransferFrom(msg.sender, address(this), amountDesired0);
            IERC20(token0).safeApprove(address(positionManager),0);
            IERC20(token0).safeApprove(address(positionManager),amountDesired0);
        }

        if (token1 != WETH) {
            IERC20(token1).safeTransferFrom(msg.sender, address(this), amountDesired1);
            IERC20(token1).safeApprove(address(positionManager),0);
            IERC20(token1).safeApprove(address(positionManager),amountDesired1);
        }

        (uint128 liquidity, uint256 amount0, uint256 amount1) = positionManager.increaseLiquidity{value: msg.value}(increaseParams);
        positionManager.refundETH();

        // update user mapping
        UserInfo memory userElement = userMapping[msg.sender];
        userElement.liquidity = liquidity - totalLiquidity;
        userElement.earnTimestamp = block.timestamp + 60 * 60 *24;

        // check against the mapping
        if (isUser[msg.sender] == false) {
            // push the unique item to the array
            userList.push(msg.sender);
            isUser[msg.sender] = true;
        }

        // send back tokens
        if (token0 == WETH && (msg.value-amount0 > 0)) {
            payable(msg.sender).transfer(msg.value-amount0);
        }
        if (token1 == WETH && (msg.value-amount1 > 0)) {
            payable(msg.sender).transfer(msg.value-amount1 );
        }
        if (token0 != WETH && amountDesired0 - amount0 > 0) {
            IERC20(token0).safeTransfer(msg.sender, amountDesired0 - amount0);
        }
        if (token1 != WETH && amountDesired1 - amount1 > 0) {
            IERC20(token1).safeTransfer(msg.sender, amountDesired1 - amount1);
        }

        totalLiquidity += liquidity;
        totalAmount0 += amount0;
        totalAmount1 += amount1;

        emit IncreaseLiquidity(amount0, amount1, liquidity, msg.sender);
    }

    // user function to decrease funds from the contract also will be called by contract to readjust borders
    function decreaseLiquidity(uint amount0Min, uint amount1Min, uint slippagePercent, uint128 liquidity)
    public
    payable
    returns
    (
        uint amount0,
        uint amount1
    )
    {
        //get user
        UserInfo memory userElement = userMapping[msg.sender];
        if (msg.sender != (address(this))) {
            require(liquidity >= userElement.liquidity);
        }

        INonfungiblePositionManager.DecreaseLiquidityParams memory decreaseParams = INonfungiblePositionManager.DecreaseLiquidityParams({
            amount1Min : amount1Min * slippagePercent / 10000,
            amount0Min : amount0Min * slippagePercent / 10000,
            tokenId : currentTokenId,
            liquidity : liquidity,
            deadline : block.timestamp + 60 * 10
        });

        (amount0, amount1) = positionManager.decreaseLiquidity(decreaseParams);
        positionManager.unwrapWETH9(0, address(this));

        if(token0 != WETH) {
            positionManager.sweepToken(token0, 0, address(this));
        }
        if(token1 != WETH) {
            positionManager.sweepToken(token1, 0, address(this));
        }

        totalAmount1 -= amount1;
        totalAmount0 -= amount0;
        totalLiquidity -= liquidity;

        // normal user processing
        if (msg.sender != address(this)) {
            // fees
            // get user stats
            (, , uint val3,) = IYieldManager(yieldManager).getUserFactors(
                msg.sender,
                0
            );

            uint mgmtFee0 = (val3 * amount0) / 100 / 100;
            uint sponsorFee0;
            uint mgmtFee1 = (val3 * amount1) / 100 / 100;
            uint sponsorFee1;

            // get sponsor
            address sponsor = IYieldManager(yieldManager).getAffiliate(owner);
            // get sponsor stats
            if (sponsor != address(0)) {
                (, uint sval2,, ) = IYieldManager(yieldManager)
                .getUserFactors(sponsor, 1);
                sponsorFee0 = (mgmtFee0 * sval2) / 100 / 100;
                mgmtFee0 -= sponsorFee0;
                sponsorFee1 = (mgmtFee1 * sval2) / 100 / 100;
                mgmtFee1 -= sponsorFee1;
            }

            // update user mapping
            UserInfo memory userElementOwner = userMapping[owner];

            // send back tokens
            if (token0 == WETH && (amount0 - mgmtFee0 - sponsorFee0 > 0)) {
                payable(msg.sender).transfer(amount0 - mgmtFee0 - sponsorFee0);
                userElementOwner.token0Balance += mgmtFee0;

                if (sponsor != address(0) && sponsorFee0 != 0) {
                    payable(sponsor).transfer(sponsorFee0);
                }
            }
            if (token1 == WETH && (amount1 - mgmtFee1 - sponsorFee1 > 0)) {
                payable(msg.sender).transfer(amount1 - mgmtFee1 - sponsorFee1);
                userElementOwner.token1Balance += mgmtFee1;

                if (sponsor != address(0) && sponsorFee1 != 0) {
                    payable(sponsor).transfer(sponsorFee1);
                }
            }
            if (token0 != WETH && amount0 - mgmtFee0 - sponsorFee0 > 0) {
                IERC20(token0).safeTransfer(msg.sender, amount0 - mgmtFee0 - sponsorFee0);
                userElementOwner.token0Balance += mgmtFee0;

                if (sponsor != address(0) && sponsorFee0 != 0) {
                    IERC20(token0).transfer(sponsor, sponsorFee0);
                }
            }
            if (token1 != WETH && amount1 - mgmtFee1 - sponsorFee1 > 0) {
                IERC20(token1).safeTransfer(msg.sender, amount1 - mgmtFee1 - sponsorFee1);
                userElementOwner.token1Balance += mgmtFee1;

                if (sponsor != address(0) && sponsorFee1 != 0) {
                    IERC20(token0).transfer(sponsor, sponsorFee1);
                }
            }

            // housekeeping
            userElement.liquidity -= liquidity;

            // if no liquidity we remove user
            if (userElement.liquidity == 0) {
                for (uint i=0; i <userList.length; i++) {
                    if (userList[i] == msg.sender) {
                        delete userList[i];
                        break;
                    }
                }
                isUser[msg.sender] = false;
            }
        }

        emit RemovedLiquidity(amount0, amount1, liquidity, msg.sender);
    }

    // public function to collect fees everyone can all (maybe bot once a week)
    function collect() public payable returns
    (
        uint256 amount0,
        uint256 amount1)
    {
        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            amount0Max : type(uint128).max,
            amount1Max : type(uint128).max,
            tokenId : currentTokenId,
            recipient: address(this)
        });

        (amount0, amount1) = positionManager.collect(collectParams);
        positionManager.unwrapWETH9(0, address(this));

        if(token0 != WETH) {
            positionManager.sweepToken(token0, 0, address(this));
        }
        if(token1 != WETH) {
            positionManager.sweepToken(token1, 0, address(this));
        }

        for (uint i=0; i <userList.length; i++) {
            UserInfo memory userElement = userMapping[userList[i]];

            // only if grace period is over we account
            if (userElement.earnTimestamp <= block.timestamp) {
                uint share0 = amount0 * userElement.liquidity / totalLiquidity;
                uint share1 = amount1 * userElement.liquidity / totalLiquidity;

                userElement.token0Balance += share0;
                userElement.token1Balance += share1;
            }
        }
    }

    // public function for user to collect their shares
    function userCollect() external {
        //get user
        UserInfo memory userElement = userMapping[msg.sender];
        uint token0Balance = userElement.token0Balance;
        uint token1Balance = userElement.token1Balance;

        if(msg.sender != owner) {
            (, uint val2,,) = IYieldManager(yieldManager).getUserFactors(
                msg.sender,
                0
            );

            uint perfFee0 = (val2 * token0Balance) / 100 / 100;
            uint sPerfFee0;

            uint perfFee1 = (val2 * token1Balance) / 100 / 100;
            uint sPerfFee1;

            address sponsor = IYieldManager(yieldManager).getAffiliate(owner);

            // get sponsor stats
            if (sponsor != address(0)) {
                (uint sval1,,,) = IYieldManager(yieldManager)
                .getUserFactors(sponsor, 1);
                sPerfFee0 = (perfFee0 * sval1)  / 100 / 100;
                perfFee0 -= sPerfFee0;
                sPerfFee1 = (perfFee1 * sval1)  / 100 / 100;
                perfFee1 -= sPerfFee1;
            }

            // update user mapping
            UserInfo memory ownerElement = userMapping[owner];

            // send tokens
            if (token0 == WETH && (token0Balance - perfFee0 - sPerfFee0 > 0)) {
                payable(msg.sender).transfer(token0Balance - perfFee0 - sPerfFee0);
                ownerElement.token0Balance += perfFee0;

                if (sponsor != address(0) && sPerfFee0 != 0) {
                    payable(sponsor).transfer(sPerfFee0);
                }
            }
            if (token1 == WETH && (token1Balance -perfFee1 -sPerfFee1 > 0)) {
                payable(msg.sender).transfer(token1Balance - perfFee1 -sPerfFee1);
                ownerElement.token1Balance += perfFee1;

                if (sponsor != address(0) && sPerfFee1 != 0) {
                    payable(sponsor).transfer(sPerfFee1);
                }
            }
            if (token0 != WETH && token0Balance - perfFee0 - sPerfFee0 > 0) {
                IERC20(token0).safeTransfer(msg.sender, token0Balance -perfFee0 -sPerfFee0);
                ownerElement.token0Balance += perfFee0;

                if (sponsor != address(0) && sPerfFee0 != 0) {
                    IERC20(token0).transfer(sponsor, sPerfFee0);
                }
            }
            if (token1 != WETH && token1Balance -perfFee1 -sPerfFee1 > 0) {
                IERC20(token1).safeTransfer(msg.sender, token1Balance -perfFee1 -sPerfFee1);
                ownerElement.token1Balance += perfFee1;

                if (sponsor != address(0) && sPerfFee1 != 0) {
                    IERC20(token1).transfer(sponsor, sPerfFee1);
                }
            }
        }
        // user is owner
        else {
            // send tokens
            if (token0 == WETH && (token0Balance > 0)) {
                payable(msg.sender).transfer(token0Balance);
            }
            if (token1 == WETH && (token1Balance > 0)) {
                payable(msg.sender).transfer(token1Balance);
            }
            if (token0 != WETH && token0Balance > 0) {
                IERC20(token0).safeTransfer(msg.sender, token0Balance);

            }
            if (token1 != WETH && token1Balance > 0) {
                IERC20(token1).safeTransfer(msg.sender, token1Balance);
            }
        }

        userElement.token0Balance = 0;
        userElement.token1Balance = 0;

        emit FeesWithdrawn(token0Balance, token1Balance, msg.sender);
    }

    function changeOwner(address _newOwner) external onlyOwner {
        owner = _newOwner;
    }

    function changePositionParameter(address _newPositionManager, address _newToken0, address _newToken1, uint24 _newFee) external onlyOwner {
        positionManager = INonfungiblePositionManager(_newPositionManager);
        uniswapV3Factory = IUniswapV3Factory(positionManager.factory());
        token0 = _newToken0;
        token1 = _newToken1;
        fee = _newFee;
        uniswapV3Pool = IUniswapV3Pool(uniswapV3Factory.getPool(token0, token1, fee));
    }

    function changeYieldManager(address _newYieldManager) external onlyOwner {
        yieldManager = _newYieldManager;
    }

    function setThresholds(int24 _tickRangeThreshold, int24 _tickMoveThreshold) external onlyOwner {
        tickRangeThreshold = _tickRangeThreshold;
        tickMoveThreshold = _tickMoveThreshold;
        emit NewTickDeviation(tickMoveThreshold);
        emit NewTickDeviation(tickRangeThreshold);
    }
}

interface IYieldManager {
    function setAffiliate(address client, address sponsor) external;
    function getUserFactors(
        address user,
        uint typer
    ) external view returns (uint, uint, uint, uint);

    function getAffiliate(address client) external view returns (address);
}

