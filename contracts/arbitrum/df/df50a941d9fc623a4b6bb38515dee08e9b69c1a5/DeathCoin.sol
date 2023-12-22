// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.4;
pragma abicoder v2;


import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Ownable} from "./Ownable.sol";


import { SafeMath } from "./SafeMath.sol";
import { ERC20 } from "./ERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IUniswapV3Factory } from "./IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "./IUniswapV3Pool.sol";
import { FixedPoint96 } from "./FixedPoint96.sol";
import { ISwapRouter } from "./ISwapRouter.sol";
import { TransferHelper } from "./TransferHelper.sol";

contract DeathCoin is
    ReentrancyGuard, 
    Ownable
 {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    uint256 private deploymentTimestamp=block.timestamp;

    mapping(address => address) public poolByTokenMap;

    mapping(address => UserData) userDataMap;
    mapping(address => FissionData) fissionDataMap;
    mapping(address => TokenGroup) public tokenGroupMap; 

    address facoryAddress=0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address wethAddress=0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address deathAddress=0x3d974E7253022957fBE1034eD8d0Ee6cF664F4dF;
    ISwapRouter swapRouter=ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    constructor(){}

    //getDeathData
    function getDeathData(address account) external view returns(uint256 userDeathCount,address fissionAddress,uint256 fissionCountDeath,uint256 fissionCountReferred){
        userDeathCount=userDataMap[account].userDeathCount;
        fissionAddress=userDataMap[account].fissionAddress;
        fissionCountDeath=fissionDataMap[account].fissionCountDeath;
        fissionCountReferred=fissionDataMap[account].fissionCountReferred;
    }

    //set supplyPoolAddress
    function setSupplyPoolAddress(
        address token0,
        address token1,
        uint24 fee) external onlyOwner {

        require(token0==wethAddress||token1==wethAddress,"WETH cannot be found");
        require(token0!=address(0),"Invalid token0 address");
        require(token1!=address(0),"Invalid token1 address");
        require(token0!=token1,"Invalid token address");
        require(fee==500 || fee==3000 || fee==10000,"Invalid fee");

        IUniswapV3Factory uniswapFactory = IUniswapV3Factory(facoryAddress);
        address poolAddress = uniswapFactory.getPool(token0, token1, fee);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        require(pool.liquidity()!=0,"Zero liquidity");
        poolByTokenMap[token0==wethAddress?token1:token0]=poolAddress;
    }

    //fissionAddress =>
    struct FissionData{
        uint256 fissionCountDeath;
        uint256 fissionCountReferred;
    }

    //msg.sender =>
    struct UserData{
        uint256 userDeathCount;
        address fissionAddress;
    }


    struct TokenGroup{
        uint256 tokenCount;
        uint256 tokenCountPrice;
    }

    struct DeathNumber{
        uint256 ethPriceToken;
        uint256 ethPriceDeath;
        uint256 tokenAmount;
        uint256 k;
        uint256 tokenDecimals;
        uint256 deathDecimals;
    }

    function countDeathNumber(DeathNumber memory deathNumber) internal pure returns(uint256){
       uint256 number=deathNumber.ethPriceToken.mul(deathNumber.k).div(deathNumber.ethPriceDeath).mul(deathNumber.tokenAmount);
       number = number.mul(10**deathNumber.deathDecimals).div(10**deathNumber.tokenDecimals).div(10**18);
       return number;
    }



    function fissionAdd(uint256 number1,uint256 number2) internal pure returns(uint256 fissionNumber){
        fissionNumber= number1.add(number2);
    }

    //exchange
    function exchangeDeath(address tokenAddress,address fissionAddress,uint256 tokenAmount)
        external
        nonReentrant
    {

        //check address and amount
        require(poolByTokenMap[tokenAddress]!=address(0),"TokenAddress not configured");
        require(tokenAmount > 0, "Invalid tokenAmount");

        //check tokenAddress is not deathAddress
        require(tokenAddress!=deathAddress,"Do not use Death Token");

        //get token unit price
        (uint256 ethPriceToken , , ) = getSwapPrice(tokenAddress);
        (uint256 ethPriceDeath , , ) = getSwapPrice(deathAddress);
        require(ethPriceToken > 0, "Token is not liquid");
        require(ethPriceDeath > 0, "Death is not liquid");

        //Calculate the number of deathNumber
        // uint256 totalSupplyToken= ERC20(tokenAddress).totalSupply().div(10**ERC20(tokenAddress).decimals());
        // uint256 totalSupplyDeath= ERC20(deathAddress).totalSupply().div(10**ERC20(deathAddress).decimals());
        uint256 k=getK();
        //uint256 deathNumber= totalSupplyToken.mul(ethPriceToken).mul(1e18).div(totalSupplyDeath.mul(ethPriceDeath)).mul(k).div(1e18).mul(tokenAmount).div(1e18);
        DeathNumber memory dN;
        // dN.totalSupplyToken=totalSupplyToken;
        // dN.totalSupplyDeath=totalSupplyDeath;
        dN.ethPriceToken=ethPriceToken;
        dN.ethPriceDeath=ethPriceDeath;
        dN.tokenAmount=tokenAmount;
        dN.k=k;
        dN.tokenDecimals=ERC20(tokenAddress).decimals();
        dN.deathDecimals=ERC20(deathAddress).decimals();
        uint256 deathNumber=countDeathNumber(dN); 
        uint256 deathNumberFission=deathNumber.div(100);

        //check user balanceOf
        require(ERC20(tokenAddress).balanceOf(msg.sender)>0,"Insufficient Balance");

        //Send Death for user
        uint256 deathBalance = ERC20(deathAddress).balanceOf(address(this));
        require(deathBalance > 0,"Death Token Insufficient supply");


        //TokenGroup Count
        TokenGroup storage tokenGroup= tokenGroupMap[tokenAddress];
        tokenGroup.tokenCount=tokenGroup.tokenCount.add(tokenAmount);
        tokenGroup.tokenCountPrice=tokenGroup.tokenCountPrice.add(tokenAmount.mul(ethPriceToken));


        UserData storage myUserData = userDataMap[msg.sender];
        if(fissionAddress!=address(0)){
            if(myUserData.fissionAddress==address(0)){
                if(fissionAddress==msg.sender){
                    require(deathNumber<=deathBalance,"Low death balance");
                    myUserData.userDeathCount=myUserData.userDeathCount.add(deathNumber);
                }else{
                    require(deathNumber.add(deathNumberFission)<=deathBalance,"Low death balance");
                    myUserData.userDeathCount=myUserData.userDeathCount.add(deathNumber);

                    myUserData.fissionAddress=fissionAddress;
                    //fissionDataMap[fissionAddress].fissionCountReferred=fissionDataMap[fissionAddress].fissionCountReferred.add(1);
                    fissionDataMap[fissionAddress].fissionCountReferred=fissionAdd(fissionDataMap[fissionAddress].fissionCountReferred,1);
                    //fissionDataMap[fissionAddress].fissionCountDeath=fissionDataMap[fissionAddress].fissionCountDeath.add(deathNumberFission);
                    fissionDataMap[fissionAddress].fissionCountDeath=fissionAdd(fissionDataMap[fissionAddress].fissionCountDeath,deathNumberFission);
                    ERC20(deathAddress).safeTransfer(fissionAddress, deathNumberFission);
                }
            }else{
                require(deathNumber.add(deathNumberFission)<=deathBalance,"Low death balance");
                myUserData.userDeathCount=myUserData.userDeathCount.add(deathNumber);
                fissionDataMap[myUserData.fissionAddress].fissionCountDeath=fissionDataMap[myUserData.fissionAddress].fissionCountDeath.add(deathNumberFission);
                ERC20(deathAddress).safeTransfer(myUserData.fissionAddress, deathNumberFission);
            }
        }else{
            require(deathNumber<=deathBalance,"Low death balance");
            myUserData.userDeathCount=myUserData.userDeathCount.add(deathNumber);
        }

        transDeath(tokenAddress,tokenAmount,deathNumber);

        //0.1ether pass
        uint256 tokenBalance = ERC20(tokenAddress).balanceOf(address(this));
        if(tokenBalance.mul(ethPriceToken).div(10**ERC20(tokenAddress).decimals())>=(1e18/10)){
            swapTokens(tokenAddress,deathAddress,tokenBalance);
        }

    }

    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountNumber
    ) public returns (uint256 amountOut) {
        (uint256 inPrice ,  ,uint24 feeIn) = getSwapPrice(tokenIn);
        (uint256 outPrice , ,uint24 feeOut) = getSwapPrice(tokenOut);
        require(inPrice > 0, "Token is not liquid");
        require(outPrice > 0, "Death is not liquid");

        ERC20(tokenIn).approve(address(swapRouter), amountNumber);

        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(tokenIn, feeIn, wethAddress, feeOut, tokenOut),
                recipient: address(this),
                deadline: block.timestamp + 60*5,
                amountIn: amountNumber,
                amountOutMinimum: 0
            });

        // Executes the swap.
        amountOut = swapRouter.exactInput(params);

    }



    function transDeath(address tokenAddress,uint256 tokenAmount,uint256 deathNumber) internal {
        // transferFrom  ERC20token to recipient address(this)
        ERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), tokenAmount);
        // safeTransfer DeathToken to user
        ERC20(deathAddress).safeTransfer(msg.sender, deathNumber);
    }

    struct SwapPrice {
        uint256 tokenBalance0;
        uint256 tokenBalance1;
        uint160 sqrtPriceX96;
        uint160 liquidity;
        uint256 ethPrice;
    }

    //Get the pool through the factory
    function getSwapPoolData(
        address token0,
        address token1,
        uint24 fee
    ) external view returns (SwapPrice memory swapPrice) {

        require(token0!=address(0),"Invalid token0 address");
        require(token1!=address(0),"Invalid token1 address");
        require(token0!=token1,"Invalid token address");
        require(fee==500 || fee==3000 || fee==10000,"Invalid fee");

        IUniswapV3Factory uniswapFactory = IUniswapV3Factory(facoryAddress);
        address poolAddress = uniswapFactory.getPool(token0, token1, fee);
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        require(pool.liquidity()!=0,"Zero liquidity");

        //get balanceOf
        uint256 tokenBalance0 = ERC20(pool.token0()).balanceOf(poolAddress);
        uint256 tokenBalance1 = ERC20(pool.token1()).balanceOf(poolAddress);
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        uint256 p =  uint256(sqrtPriceX96).mul(1e18).div(2**96).mul(sqrtPriceX96).div(2**96);
        swapPrice.ethPrice = (p * 10 ** ERC20(pool.token0()).decimals()).div(10 ** ERC20(pool.token1()).decimals());
        if(wethAddress==pool.token0()){
            swapPrice.ethPrice=uint256(1e36).div(swapPrice.ethPrice);
        }

        swapPrice.tokenBalance0 = tokenBalance0;
        swapPrice.tokenBalance1 = tokenBalance1;
        swapPrice.sqrtPriceX96 = sqrtPriceX96;
        swapPrice.liquidity = pool.liquidity();
        return swapPrice;
    }

    //getSwapPrice
    function getSwapPrice(
        address tokenAddress
    ) public view returns (uint256 ethPrice,address poolAddress,uint24 fee) {
        require(poolByTokenMap[tokenAddress]!=address(0),"tokenAddress not configured");
        //get pool
        IUniswapV3Pool pool = IUniswapV3Pool(poolByTokenMap[tokenAddress]);
        require(pool.liquidity()!=0,"Zero liquidity");
        (uint160 sqrtPriceX96,, , , , , ) = pool.slot0();
        uint256 p =  uint256(sqrtPriceX96).mul(1e18).div(2**96).mul(sqrtPriceX96).div(2**96);
        ethPrice = (p * 10 ** ERC20(pool.token0()).decimals()).div(10 ** ERC20(pool.token1()).decimals());
        if(wethAddress==pool.token0()){
            ethPrice=uint256(1e36).div(ethPrice);
        }
       
        poolAddress=poolByTokenMap[tokenAddress];
        fee=pool.fee();
    }

    //getDaysSinceDeployment
    function getDaysSinceDeployment() private view returns (uint256) {
        uint256 secondsInDay = 86400;
        uint256 elapsedSeconds = block.timestamp - deploymentTimestamp;
        uint256 elapsedDays = elapsedSeconds / secondsInDay;
        return elapsedDays;
    }

    function getK() public view returns (uint256 k) {
        uint256 countDay = getDaysSinceDeployment();
        if(countDay>364){
            return 1e18;
        }else{
            return (15*1e17  - (15 - 10) *   (countDay*1e17) / 365);
        }
    }



}

