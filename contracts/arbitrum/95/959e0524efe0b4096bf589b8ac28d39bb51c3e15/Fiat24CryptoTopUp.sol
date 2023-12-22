// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./AccessControlUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./SafeMath.sol";
import "./IERC20.sol";
import "./IUniswapV3Factory.sol";
import "./IUniswapV3Pool.sol";
import "./ISwapRouter.sol";
import "./IPeripheryPaymentsWithFee.sol";
import "./IQuoter.sol";
import "./TransferHelper.sol";
import "./Fiat24Account.sol";
import "./Fiat24USD.sol";
import "./SanctionsList.sol";
import "./IF24TimeLock.sol";

contract Fiat24CryptoTopUp is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeMath for uint256;

    struct Quota {
        uint256 quota;
        uint256 quotaBegin;
        bool isAvailable;
    }

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant THIRTYDAYS = 2592000;
    uint256 public constant FOURDECIMALS = 10000;

    // // RINKEBY ADDRESSES 
    // address public constant WETH_ADDRESS = 0xc778417E063141139Fce010982780140Aa0cD5Ab;
    // address public constant USDC_ADDRESS = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    // address public constant USD24_ADDRESS = 0xB26E32b98FbA7b0E04A58f32CE69AB63fAA36B0d;

    // // ARBITRUM MAINNET ADDRESSES 
    address public constant WETH_ADDRESS = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant USDC_ADDRESS = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant USD24_ADDRESS = 0xbE00f3db78688d9704BCb4e0a827aea3a9Cc0D62;

    // ARBITRUM RINKEBY ADDRESSES
    // address public constant WETH_ADDRESS = 0xB47e6A5f8b33b3F17603C83a0535A9dcD7E32681;
    // address public constant USDC_ADDRESS = 0x34DEdF48f3eBb0Ab4B32FFd5F815A26a7Dcd0cE0;
    // address public constant USD24_ADDRESS = 0xCab2D215C64DC3860362ae9919aeef2E81e6C80a;

    uint256 public constant TREASURY_ACCOUNT_ID = 9203;

    address[] public outputTokens; 

    IUniswapV3Factory public constant uniswapFactory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    ISwapRouter public constant swapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IPeripheryPaymentsWithFee public constant peripheryPayments = IPeripheryPaymentsWithFee(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IQuoter public constant quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6); 

    address public treasuryDeskAddress;
    address public cryptoDeskAddress;
    address public f24DeskAddress;

    uint256 public fee;
    uint256 public maxQuota;
    
    mapping (uint256 => Quota) public quotas; 

    Fiat24Account fiat24account;
    IERC20 f24;
    Fiat24USD usd24;

    uint256 slippage;

    bool public sanctionCheck;
    address public sanctionContract;

    //F24 airdrop
    uint256 public f24AirdropStart; // timestamp
    uint256 public f24PerUSDC;
    bool public f24AirdropPaused;

    //F24 timelock
    IF24TimeLock public f24TimeLock;

    //Max USDC top-up amount
    uint256 public maxTopUpAmount;

    function initialize(address fiat24AccountAddress_, 
                        address f24Address_,
                        address usd24Address_,
                        address treasuryDeskAddress_, 
                        address cryptoDeskAddress_,
                        address f24DeskAddress_,
                        uint256 fee_,
                        uint256 maxQuota_, 
                        uint256 slippage_,
                        address sanctionContract_,
                        uint256 f24AirdropStart_,
                        uint256 f24PerUSDC_) public initializer {
        __AccessControl_init_unchained();
        __Pausable_init_unchained();
        _setupRole(OPERATOR_ROLE, msg.sender);
        fiat24account = Fiat24Account(fiat24AccountAddress_);
        f24 = IERC20(f24Address_);
        usd24 = Fiat24USD(usd24Address_);
        treasuryDeskAddress = treasuryDeskAddress_;
        cryptoDeskAddress = cryptoDeskAddress_;
        f24DeskAddress = f24DeskAddress_;
        fee = fee_;
        maxQuota = maxQuota_;
        slippage = slippage_;
        sanctionContract = sanctionContract_;
        sanctionCheck = false;
        f24AirdropStart = f24AirdropStart_;
        f24PerUSDC = f24PerUSDC_;
        f24AirdropPaused = false;

        // ARBITRUM MAINNET OUTPUT TOKENS
        outputTokens = [
                address(0xbE00f3db78688d9704BCb4e0a827aea3a9Cc0D62),
                0x2c5d06f591D0d8cd43Ac232c2B654475a142c7DA,
                0xd41F1f0cf89fD239ca4c1F8E8ADA46345c86b0a4,
                0x5fc17218196581864974574d715cFC7334794cBE
        ];

        // ARBITRUM RINKEBY OUTPUT TOKENS
        // outputTokens = [
        //         address(0xCab2D215C64DC3860362ae9919aeef2E81e6C80a),
        //         0x2c5d06f591D0d8cd43Ac232c2B654475a142c7DA,
        //         0xDecf935e04348fDb9724EbE6Ee4F97B3DC0C4beB,
        //         0x89bB17C627B7fB3fAD87534bF5DF45191247Fc7A
        // ];

    }

    function topUpCryptoViaUSDC(address tokenIn, address tokenOut, uint256 amount) external returns(uint256){
        require(!paused(), "Fiat24CryptoTopUp: top-up currently suspended");
        require(amount > 0, "Fiat24CryptoTopUp: amount must be greater than zero (0)");
        require(isOutputTokenValid(tokenOut), "Fiat24CryptoTopUp: invalid output Token");
        if(sanctionCheck) {
            SanctionsList sanctionsList = SanctionsList(sanctionContract);
            require(!sanctionsList.isSanctioned(msg.sender), "Fiat24CryptoTopUp: top-up from sanctioned address");
        }
        uint256 tokenId = getTokenByAddress(msg.sender);
        require(tokenId != 0, "Fiat24CryptoTopUp: msg.sender has no Fiat24 account");
        require(tokenEligibleForCryptoTopUp(tokenId), "Fiat24CryptoTopUp: Fiat24 account not eligible for top-up");
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amount);
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amount);
        uint256 usdcAmount;
        if(tokenIn != USDC_ADDRESS) {
            uint24 poolFee = getPoolFeeOfMostLiquidPool(tokenIn, USDC_ADDRESS);
            require(poolFee != 0, "Fiat24CryptoTopUp: no USDC pool available");
            uint256 amountOutMininumUSDC = getQuote(tokenIn, USDC_ADDRESS, poolFee, amount);
            ISwapRouter.ExactInputSingleParams memory params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: USDC_ADDRESS,
                    fee: poolFee,
                    recipient: address(this),
                    deadline: block.timestamp + 15,
                    amountIn: amount,
                    amountOutMinimum: amountOutMininumUSDC.sub(amountOutMininumUSDC.mul(slippage).div(100)),
                    sqrtPriceLimitX96: 0
                });
            usdcAmount = swapRouter.exactInputSingle(params);
            require(usdcAmount > 0, "Fiat24CryptoTopUp: tokenIn/USDC amount <= 0");
        } else {
            usdcAmount = amount;
        }

        require(usdcAmount <= maxTopUpAmount, "Fiat24CryptoTopUp: USDC amount exceeds max. USDC top-up amount");

        //USDC->USD24
        uint256 usd24Amount = getTopUpAmount(tokenId, usdcAmount);
        TransferHelper.safeTransfer(USDC_ADDRESS, cryptoDeskAddress, usdcAmount);
        TransferHelper.safeTransferFrom(USD24_ADDRESS, treasuryDeskAddress, address(this), usd24Amount);
        TransferHelper.safeTransferFrom(USD24_ADDRESS, treasuryDeskAddress, fiat24account.ownerOf(TREASURY_ACCOUNT_ID), calculateFee(tokenId, usdcAmount).div(FOURDECIMALS));
        updateQuota(tokenId, usdcAmount);
        if(!f24AirdropPaused) {
            f24Airdrop(usdcAmount);
        }

        //USD24->tokenOut
        uint256 outputAmount;
        if(tokenOut == USD24_ADDRESS) {
            outputAmount = usd24Amount;
        } else {
            uint24 poolFee = getPoolFeeOfMostLiquidPool(USD24_ADDRESS, tokenOut);
            require(poolFee != 0, "Fiat24CryptoTopUp: no USD24/tokenOut pool available");
            uint256 amountOutMininum = getQuote(USD24_ADDRESS, tokenOut, 3000, usd24Amount);
            TransferHelper.safeApprove(USD24_ADDRESS, address(swapRouter), usd24Amount);
            ISwapRouter.ExactInputSingleParams memory params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: USD24_ADDRESS,
                    tokenOut: tokenOut,
                    fee: 3000,
                    recipient: address(this),
                    deadline: block.timestamp + 15,
                    amountIn: usd24Amount,
                    amountOutMinimum: amountOutMininum.sub(amountOutMininum.mul(slippage).div(100)),
                    sqrtPriceLimitX96: 0
                });
            outputAmount = swapRouter.exactInputSingle(params);
            require(outputAmount > 0, "Fiat24CryptoTopUp:  USD24/tokenOut amount <= 0");
        }
        TransferHelper.safeTransfer(tokenOut, msg.sender, outputAmount);
        return outputAmount;
    }

    function topUpCryptoViaETH(address tokenIn, address tokenOut, uint256 amount) external returns(uint256){
        require(!paused(), "Fiat24CryptoTopUp: top-up currently suspended");
        require(amount > 0, "Fiat24CryptoTopUp: amount must be greater than zero (0)");
        require(isOutputTokenValid(tokenOut), "Fiat24CryptoTopUp: invalid output Token");
        if(sanctionCheck) {
            SanctionsList sanctionsList = SanctionsList(sanctionContract);
            require(!sanctionsList.isSanctioned(msg.sender), "Fiat24CryptoTopUp: top-up from sanctioned address");
        }
        uint256 tokenId = getTokenByAddress(msg.sender);
        require(tokenId != 0, "Fiat24CryptoTopUp: msg.sender has no Fiat24 account");
        require(tokenEligibleForCryptoTopUp(tokenId), "Fiat24CryptoTopUp: Fiat24 account not eligible for top-up");

        // TokenIn->WETH
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amount);
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amount);
        uint256 outputAmount;
        uint24 poolFee = getPoolFeeOfMostLiquidPool(tokenIn, WETH_ADDRESS);
        require(poolFee != 0, "Fiat24CryptoTopUp: no tokenIn/ETH pool available");
        uint256 amountOutMininumETH = getQuote(tokenIn, WETH_ADDRESS, poolFee, amount);
        ISwapRouter.ExactInputSingleParams memory paramsTokeninToEth =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: WETH_ADDRESS,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 15,
                amountIn: amount,
                amountOutMinimum: amountOutMininumETH.sub(amountOutMininumETH.mul(slippage).div(100)),
                sqrtPriceLimitX96: 0
            });
        outputAmount = swapRouter.exactInputSingle(paramsTokeninToEth);
        require(outputAmount > 0, "Fiat24CryptoTopUp: tokenIn/WETH output amount <= 0");

        // WETH->USDC
        TransferHelper.safeApprove(WETH_ADDRESS, address(swapRouter), outputAmount);
        poolFee = getPoolFeeOfMostLiquidPool(WETH_ADDRESS, USDC_ADDRESS);
        require(poolFee != 0, "Fiat24CryptoTopUp: no WETH/USDC pool available");
        uint256 amountOutMininumUSDC = getQuote(WETH_ADDRESS, USDC_ADDRESS, poolFee, outputAmount);
        ISwapRouter.ExactInputSingleParams memory paramsWethToUsdc =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH_ADDRESS,
                tokenOut: USDC_ADDRESS,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 15,
                amountIn: outputAmount,
                amountOutMinimum: amountOutMininumUSDC.sub(amountOutMininumUSDC.mul(slippage).div(100)),
                sqrtPriceLimitX96: 0
            });
        outputAmount = swapRouter.exactInputSingle(paramsWethToUsdc);
        require(outputAmount > 0, "Fiat24CryptoTopUp: WETH/USDC output amount <= 0");
        require(outputAmount <= maxTopUpAmount, "Fiat24CryptoTopUp: USDC amount exceeds max. USDC top-up amount");

        //USDC->USD24
        uint256 usd24Amount = getTopUpAmount(tokenId, outputAmount);
        TransferHelper.safeTransfer(USDC_ADDRESS, cryptoDeskAddress, outputAmount);
        TransferHelper.safeTransferFrom(USD24_ADDRESS, treasuryDeskAddress, address(this), usd24Amount);
        TransferHelper.safeTransferFrom(USD24_ADDRESS, treasuryDeskAddress, fiat24account.ownerOf(TREASURY_ACCOUNT_ID), calculateFee(tokenId, outputAmount).div(FOURDECIMALS));
        updateQuota(tokenId, outputAmount);
        if(!f24AirdropPaused) {
            f24Airdrop(outputAmount);
        }

        //USD24->tokenOut
        if(tokenOut == USD24_ADDRESS) {
            outputAmount = usd24Amount;
        } else {
            poolFee = getPoolFeeOfMostLiquidPool(USD24_ADDRESS, tokenOut);
            require(poolFee != 0, "Fiat24CryptoTopUp: no USD24/tokenOut pool available");
            uint256 amountOutMininum = getQuote(USD24_ADDRESS, tokenOut, 3000, usd24Amount);
            TransferHelper.safeApprove(USD24_ADDRESS, address(swapRouter), usd24Amount);
            ISwapRouter.ExactInputSingleParams memory params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: USD24_ADDRESS,
                    tokenOut: tokenOut,
                    fee: poolFee,
                    recipient: address(this),
                    deadline: block.timestamp + 15,
                    amountIn: usd24Amount,
                    amountOutMinimum: amountOutMininum.sub(amountOutMininum.mul(slippage).div(100)),
                    sqrtPriceLimitX96: 0
                });
            outputAmount = swapRouter.exactInputSingle(params);
            require(outputAmount > 0, "Fiat24CryptoTopUp: USD24/tokenOut output amount <= 0");
        }
        TransferHelper.safeTransfer(tokenOut, msg.sender, outputAmount);
        return outputAmount;
    }

    function topUpETH(address tokenOut) external payable returns(uint256){
        require(!paused(), "Fiat24CryptoTopUp: top-up currently suspended");
        require(msg.value > 0, "Fiat24CryptoTopUp: amount must not be zero (0)");
        require(isOutputTokenValid(tokenOut), "Fiat24CryptoTopUp: invalid output Token");
        if(sanctionCheck) {
            SanctionsList sanctionsList = SanctionsList(sanctionContract);
            require(!sanctionsList.isSanctioned(msg.sender), "Fiat24CryptoTopUp: top-up from sanctioned address");
        }
        uint256 tokenId = getTokenByAddress(msg.sender);
        require(tokenId != 0, "Fiat24CryptoTopUp: msg.sender has no Fiat24 account");
        require(tokenEligibleForCryptoTopUp(tokenId), "Fiat24CryptoTopUp: Fiat24 account not eligible for top-up");

        // ETH->USDC
        uint24 poolFee = getPoolFeeOfMostLiquidPool(WETH_ADDRESS, USDC_ADDRESS);
        require(poolFee != 0, "Fiat24CryptoTopUp: no WETH/USDC pool available");
        uint256 amountOutMininumUSDC = getQuote(WETH_ADDRESS, USDC_ADDRESS, 3000, msg.value);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH_ADDRESS,
                tokenOut: USDC_ADDRESS,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp + 15,
                amountIn: msg.value,
                amountOutMinimum: amountOutMininumUSDC.sub(amountOutMininumUSDC.mul(slippage).div(100)),
                sqrtPriceLimitX96: 0
            });
        uint256 usdcAmount = swapRouter.exactInputSingle{value: msg.value}(params);
        peripheryPayments.refundETH();

        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Fiat24CryptoTopUp: ETH refund failed");
        require(usdcAmount > 0, "Fiat24CryptoTopUp: WETH/USDC output amount <= 0");
        require(usdcAmount <= maxTopUpAmount, "Fiat24CryptoTopUp: USDC amount exceeds max. USDC top-up amount");

        // USDC->USD24
        uint256 usd24Amount = getTopUpAmount(tokenId, usdcAmount);
        TransferHelper.safeTransfer(USDC_ADDRESS, cryptoDeskAddress, usdcAmount);
        TransferHelper.safeTransferFrom(USD24_ADDRESS, treasuryDeskAddress, address(this), usd24Amount);
        TransferHelper.safeTransferFrom(USD24_ADDRESS, treasuryDeskAddress, fiat24account.ownerOf(TREASURY_ACCOUNT_ID), calculateFee(tokenId, usdcAmount).div(FOURDECIMALS));
        updateQuota(tokenId, usdcAmount);
        if(!f24AirdropPaused) {
            f24Airdrop(usdcAmount);
        }

        // USD24->tokenOut
        uint256 outputAmount;
        if(tokenOut == USD24_ADDRESS) {
            outputAmount = usd24Amount;
        } else {
            poolFee = getPoolFeeOfMostLiquidPool(USD24_ADDRESS, tokenOut);
            require(poolFee != 0, "Fiat24CryptoTopUp: no USD24/tokenOut pool available");
            uint256 amountOutMininum = getQuote(USD24_ADDRESS, tokenOut, 3000, usd24Amount);
            TransferHelper.safeApprove(USD24_ADDRESS, address(swapRouter), usd24Amount);
            params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: USD24_ADDRESS,
                    tokenOut: tokenOut,
                    fee: poolFee,
                    recipient: address(this),
                    deadline: block.timestamp + 15,
                    amountIn: usd24Amount,
                    amountOutMinimum: amountOutMininum.sub(amountOutMininum.mul(slippage).div(100)),
                    sqrtPriceLimitX96: 0
                });
            outputAmount = swapRouter.exactInputSingle(params);
            require(outputAmount > 0, "Fiat24CryptoTopUp: USD24/outputToken output amount <= 0");
        }
        TransferHelper.safeTransfer(tokenOut, msg.sender, outputAmount);
        return outputAmount;
    }

    function getTopUpAmount(uint256 tokenId_, uint256 usdcAmount_) public view returns(uint256) {
        uint256 topUpAmount;
        uint256 usd24Amount = usdcAmount_.div(FOURDECIMALS);
        if(tokenEligibleForCryptoTopUp(tokenId_) && fiat24account.checkLimit(tokenId_, usd24.convertToChf(usd24Amount))) {
            (,topUpAmount) = usdcAmount_.trySub(calculateFee(tokenId_,  usdcAmount_));
        } else {
            topUpAmount = 0;
        }
        return topUpAmount.div(FOURDECIMALS);
    }

    function calculateFee(uint256 tokenId_, uint256 usdcAmount_) public view returns(uint256) {
        uint256 f24Balance = getF24LockedAmount(tokenId_).mul(FOURDECIMALS);
        (,uint256 freeTier) = f24Balance.trySub(getUsedQuota(tokenId_));
        (,uint256 feeTier) = usdcAmount_.trySub(freeTier);
        return feeTier.mul(fee).div(100);
    }

    function getTiers(uint256 tokenId_, uint256 usdcAmount_) external view returns(uint256, uint256) {
        uint256 f24Balance = getF24LockedAmount(tokenId_).mul(FOURDECIMALS);
        (,uint256 freeQuota) = f24Balance.trySub(getUsedQuota(tokenId_));
        (,uint256 standardTier) = usdcAmount_.trySub(freeQuota);
        (,uint256 freeTier) = usdcAmount_.trySub(standardTier);
        return (standardTier, freeTier);
    }

    function getQuote(address tokenIn, address tokenOut, uint24 fee_, uint256 amount) public payable returns(uint256) {
        return quoter.quoteExactInputSingle(
            tokenIn,
            tokenOut,
            fee_,
            amount,
            0
        ); 
    }

    function getMaxQuota(uint256 tokenId_) public view returns(uint256) {
        uint256 quota = 0;
        if(tokenEligibleForCryptoTopUp(tokenId_)) {
            if(quotas[tokenId_].isAvailable) {
                uint256 quotaEnd = quotas[tokenId_].quotaBegin + THIRTYDAYS;
                if(block.timestamp > quotaEnd) {
                    quota =  maxQuota;
                } else {
                    quota = maxQuota - quotas[tokenId_].quota;
                }
            } else {
                quota = maxQuota;
            }
        } 
        return quota;
    }

    function getUsedQuota(uint256 tokenId_) public view returns(uint256) {
        uint256 quota = 0;
        if(tokenEligibleForCryptoTopUp(tokenId_)) {
            if(quotas[tokenId_].isAvailable) {
                uint256 quotaEnd = quotas[tokenId_].quotaBegin + THIRTYDAYS;
                if(quotas[tokenId_].quotaBegin == 0 || block.timestamp > quotaEnd) {
                    quota = 0;
                } else {
                    quota = quotas[tokenId_].quota;
                }
            } else {
                quota = 0;
            }
        } else {
            quota = maxQuota;
        }
        return quota;
    }
    
    function updateQuota(uint256 tokenId_, uint256 usdcAmount_) internal {
        if(quotas[tokenId_].isAvailable) {
            if((quotas[tokenId_].quotaBegin + THIRTYDAYS) < block.timestamp) {
                quotas[tokenId_].quota = usdcAmount_;
                quotas[tokenId_].quotaBegin = block.timestamp;
            } else {
                quotas[tokenId_].quota += usdcAmount_;
            }
        } else {
            quotas[tokenId_].quota = usdcAmount_;
            quotas[tokenId_].quotaBegin = block.timestamp;
            quotas[tokenId_].isAvailable = true;
        }
    }

    function tokenEligibleForCryptoTopUp(uint256 tokenId_) public view returns(bool) {
        return tokenExists(tokenId_) && 
               (fiat24account.status(tokenId_) == Fiat24Account.Status.Live ||
                fiat24account.status(tokenId_) == Fiat24Account.Status.Tourist);
    }

    function getTokenByAddress(address owner) internal view returns(uint256) {
        try fiat24account.tokenOfOwnerByIndex(owner, 0) returns(uint256 tokenid) {
            return tokenid;
        } catch Error(string memory) {
            return 0;
        } catch (bytes memory) {
            return 0;
        }
    }

    function getPoolFeeOfMostLiquidPool(address inputToken, address outputToken) public view returns(uint24) {
        uint24 feeOfMostLiquidPool = 0;
        uint128 highestLiquidity = 0;
        uint128 liquidity;
        IUniswapV3Pool pool;
        address poolAddress = uniswapFactory.getPool(inputToken, outputToken, 100);
        if(poolAddress != address(0)) {
            pool = IUniswapV3Pool(poolAddress);
            liquidity = pool.liquidity();
            if(liquidity > highestLiquidity) {
                highestLiquidity = liquidity;
                feeOfMostLiquidPool = 100;
            }
        }
        poolAddress = uniswapFactory.getPool(inputToken, outputToken, 500);
        if(poolAddress != address(0)) {
            pool = IUniswapV3Pool(poolAddress);
            liquidity = pool.liquidity();
            if(liquidity > highestLiquidity) {
                highestLiquidity = liquidity;
                feeOfMostLiquidPool = 500;
            }
        }
        poolAddress = uniswapFactory.getPool(inputToken, outputToken, 3000);
        if(poolAddress != address(0)) {
            pool = IUniswapV3Pool(poolAddress);
            liquidity = pool.liquidity();
            if(liquidity > highestLiquidity) {
                highestLiquidity = liquidity;
                feeOfMostLiquidPool = 3000;
            }
        }
        poolAddress = uniswapFactory.getPool(inputToken, outputToken, 10000);
        if(poolAddress != address(0)) {
            pool = IUniswapV3Pool(poolAddress);
            liquidity = pool.liquidity();
            if(liquidity > highestLiquidity) {
                highestLiquidity = liquidity;
                feeOfMostLiquidPool = 10000;
            }
        }
        return feeOfMostLiquidPool;
    }

    function isOutputTokenValid(address tokenOut) public view returns(bool) {
        for(uint i = 0; i < outputTokens.length; i++) {
            if(outputTokens[i] == tokenOut) {
                return true;
            }
        }
        return false;
    }

    function addOutputToken(address outputToken_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        outputTokens.push(outputToken_);
    }

    function changeCryptoDeskAddress(address cryptoDeskAddress_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        cryptoDeskAddress = cryptoDeskAddress_;
    }

    function changeTreasuryAdddress(address treasuryDeskAddress_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        treasuryDeskAddress = treasuryDeskAddress_;
    }

    function changeF24DeskAdddress(address f24DeskAddress_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        f24DeskAddress = f24DeskAddress_;
    }

    function changeFee(uint256 newFee_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        fee = newFee_;
    }

    function changeMaxQuota(uint256 maxQuota_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        maxQuota = maxQuota_;
    }

    function changeMaxTopUpAmount(uint256 maxTopUpAmount_) external {
       require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
       maxTopUpAmount = maxTopUpAmount_; 
    }

    function changeSlippage(uint256 slippage_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        slippage = slippage_;
    }

    function setSanctionCheck(bool sanctionCheck_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        sanctionCheck = sanctionCheck_;
    }

    function setSanctionCheckContract(address sanctionContract_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        sanctionContract = sanctionContract_;
    }

    function f24Airdrop(uint256 usdcAmount) internal {
        uint256 f24Balance = f24.balanceOf(f24DeskAddress);
        if(block.timestamp >= f24AirdropStart && f24Balance > 0) {
            uint256 f24Amount = usdcAmount.div(FOURDECIMALS).div(f24PerUSDC);
            f24Amount = f24Amount < f24Balance ? f24Amount : f24Balance;
            f24.transferFrom(f24DeskAddress, msg.sender, f24Amount);
        }
    }

    function pauseF24Airdrop() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        f24AirdropPaused = true;
    }

    function unpauseF24Airdrop() external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        f24AirdropPaused = false;
    }

    function changeF24AirdropStart(uint256 f24AirdropStart_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        f24AirdropStart = f24AirdropStart_;
    }

    function changeF24PerUSDC(uint256 f24PerUSDC_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        f24PerUSDC = f24PerUSDC_;
    }

    function setF24TimeLockContract(address f24TimeLockContractAddress_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        f24TimeLock = IF24TimeLock(f24TimeLockContractAddress_);
    }

    function getF24LockedAmount(uint256 tokenId_) internal view returns(uint256){
        IF24TimeLock.LockedAmount memory lockedAmount = f24TimeLock.lockedAmounts(tokenId_);
        return lockedAmount.lockedAmount;
    }

    function tokenExists(uint256 tokenId_) internal view returns(bool){
        try fiat24account.ownerOf(tokenId_) returns(address) {
            return true;
        } catch Error(string memory) {
            return false;
        } catch (bytes memory) {
            return false;
        }
    }

    function pause() public {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        _pause();
    }

    function unpause() public {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: not an operator");
        _unpause();
    }

    receive() payable external {}
}
