// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "./Pausable.sol";
import "./SafeMath.sol";
import "./TransferHelper.sol";
import "./ISwapRouter.sol";
import "./IPeripheryPaymentsWithFee.sol";
import "./IQuoter.sol";
import "./TransferHelper.sol";
import "./Fiat24Account.sol";
import "./F24.sol";
import "./Fiat24USD.sol";
import "./SanctionsList.sol";

contract Fiat24CryptoTopUp is AccessControl, Pausable {
    using SafeMath for uint256;

    struct Quota {
        uint256 quota;
        uint256 quotaBegin;
        bool isAvailable;
    }

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 public constant THIRTYDAYS = 2592000;
    uint256 public constant FOURDECIMALS = 10000;

    address public constant WETH_ADDRESS = 0xB47e6A5f8b33b3F17603C83a0535A9dcD7E32681;
    address public constant USDC_ADDRESS = 0x34DEdF48f3eBb0Ab4B32FFd5F815A26a7Dcd0cE0;
    address public constant USD24_ADDRESS = 0xCab2D215C64DC3860362ae9919aeef2E81e6C80a;

    ISwapRouter public immutable swapRouter;
    IPeripheryPaymentsWithFee public immutable peripheryPayments;
    IQuoter public immutable quoter;

    address public treasuryAddress;
    address public cryptoDeskAddress;

    uint256 public fee;
    uint256 public maxQuota;
    uint256 public minTopUpAmount;
    
    mapping (uint256 => Quota) public quotas; 

    mapping (bytes32 => bool) public tokenPairs;

    Fiat24Account fiat24account;
    F24 f24;
    Fiat24USD usd24;

    uint256 slippage;

    bool public sanctionCheck;
    address public sanctionContract;

    constructor(address fiat24AccountAddress_, 
                address f24Address_, 
                address usd24Address_,
                address swapRouterAddress_,
                address quoterAddress_, 
                address treasuryAddress_, 
                address cryptoDeskAddress_,
                uint256 fee_,
                uint256 maxQuota_, 
                uint256 minTopUpAmount_,
                uint256 slippage_,
                address sanctionContract_) {
        _setupRole(OPERATOR_ROLE, msg.sender);
        fiat24account = Fiat24Account(fiat24AccountAddress_);
        f24 = F24(f24Address_);
        usd24 = Fiat24USD(usd24Address_);
        swapRouter = ISwapRouter(swapRouterAddress_);
        quoter = IQuoter(quoterAddress_);
        peripheryPayments = IPeripheryPaymentsWithFee(swapRouterAddress_);
        treasuryAddress = treasuryAddress_;
        cryptoDeskAddress = cryptoDeskAddress_;
        fee = fee_;
        maxQuota = maxQuota_;
        minTopUpAmount = minTopUpAmount_;
        slippage = slippage_;
        sanctionContract = sanctionContract_;
        sanctionCheck = false;
    }

    function topUpCrypto(address tokenIn, address tokenOut, uint256 amount) external returns(uint256){
        require(!paused(), "Fiat24CryptoTopUp: Top-up currently suspended");
        require(isTokenPairAvailable(tokenIn, tokenOut), "Fiat24CryptoTopUp: Top-Up pair not available");
        require(amount > 0, "Fiat24CryptoTopUp: Amount must be greater than zero (0)");
        if(sanctionCheck) {
            SanctionsList sanctionsList = SanctionsList(sanctionContract);
            bool isSanctioned = sanctionsList.isSanctioned(msg.sender);
            require(!isSanctioned, "Fiat24CryptoTopUp: Top-up from sanctioned address");
        }
        uint256 tokenId = getTokenByAddress(msg.sender);
        require(tokenId != 0, "Fiat24CryptoTopUp: msg.sender has no Fiat24 account");
        require(tokenEligibleForUsdcTopUp(tokenId), "Fiat24CryptoTopUp: Fiat24 account not eligible for top-up");
        TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amount);
        TransferHelper.safeApprove(tokenIn, address(swapRouter), amount);
        uint256 usdcAmount;
        if(tokenIn != USDC_ADDRESS) {
            uint256 amountOutMininumUSDC = getQuote(tokenIn, USDC_ADDRESS, 3000, amount);
            ISwapRouter.ExactInputSingleParams memory params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: USDC_ADDRESS,
                    fee: 3000,
                    recipient: address(this),
                    deadline: block.timestamp + 15,
                    amountIn: amount,
                    amountOutMinimum: amountOutMininumUSDC.sub(amountOutMininumUSDC.mul(slippage).div(100)),
                    sqrtPriceLimitX96: 0
                });
            usdcAmount = swapRouter.exactInputSingle(params);
        } else {
            usdcAmount = amount;
        }

        //USDC->USD24
        uint256 usd24Amount = getTopUpAmount(tokenId, msg.sender, usdcAmount);
        TransferHelper.safeTransfer(USDC_ADDRESS, cryptoDeskAddress, usdcAmount);
        TransferHelper.safeTransferFrom(USD24_ADDRESS, treasuryAddress, address(this), usd24Amount);
        updateQuota(tokenId, usdcAmount);

        //USD24->tokenOut
        uint256 outputAmount;
        if(tokenOut == USD24_ADDRESS) {
            TransferHelper.safeTransfer(USD24_ADDRESS, msg.sender, usd24Amount);
            outputAmount = usd24Amount;
        } else {
            uint256 amountOutMininum = getQuote(USD24_ADDRESS, tokenOut, 3000, usd24Amount);
            TransferHelper.safeApprove(USD24_ADDRESS, address(swapRouter), usd24Amount);
            ISwapRouter.ExactInputSingleParams memory params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: USD24_ADDRESS,
                    tokenOut: tokenOut,
                    fee: 3000,
                    recipient: msg.sender,
                    deadline: block.timestamp + 15,
                    amountIn: usd24Amount,
                    amountOutMinimum: amountOutMininum,
                    sqrtPriceLimitX96: 0
                });
            outputAmount = swapRouter.exactInputSingle(params);
        }
        return outputAmount;
    }

    function topUpETH(address tokenOut) external payable returns(uint256){
        require(isTokenPairAvailable(WETH_ADDRESS, tokenOut), "Fiat24CryptoTopUp: Top-Up pair not available");
        require(msg.value > 0, "Fiat24CryptoTopUp: Amount must not be zero (0)");
        if(sanctionCheck) {
            SanctionsList sanctionsList = SanctionsList(sanctionContract);
            bool isSanctioned = sanctionsList.isSanctioned(msg.sender);
            require(!isSanctioned, "Fiat24CryptoTopUp: Top-up from sanctioned address");
        }
        uint256 tokenId = getTokenByAddress(msg.sender);
        require(tokenId != 0, "Fiat24CryptoTopUp: msg.sender has no Fiat24 account");
        require(tokenEligibleForUsdcTopUp(tokenId), "Fiat24CryptoTopUp: Fiat24 account not eligible for top-up");
        // ETH->USDC
        uint256 amountOutMininumUSDC = getQuote(WETH_ADDRESS, USDC_ADDRESS, 3000, msg.value);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH_ADDRESS,
                tokenOut: USDC_ADDRESS,
                fee: 3000,
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

        // USDC->USD24
        uint256 usd24Amount = getTopUpAmount(tokenId, msg.sender, usdcAmount);
        TransferHelper.safeTransfer(USDC_ADDRESS, cryptoDeskAddress, usdcAmount);
        TransferHelper.safeTransferFrom(USD24_ADDRESS, treasuryAddress, address(this), usd24Amount);
        updateQuota(tokenId, usdcAmount);

        // USD24->tokenOut
        uint256 outputAmount;
        if(tokenOut == USD24_ADDRESS) {
            TransferHelper.safeTransfer(USD24_ADDRESS, msg.sender, usd24Amount);
            outputAmount = usd24Amount;
        } else {
            uint256 amountOutMininum = getQuote(USD24_ADDRESS, tokenOut, 3000, usd24Amount);
            TransferHelper.safeApprove(USD24_ADDRESS, address(swapRouter), usd24Amount);
            params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: USD24_ADDRESS,
                    tokenOut: tokenOut,
                    fee: 3000,
                    recipient: msg.sender,
                    deadline: block.timestamp + 15,
                    amountIn: usd24Amount,
                    amountOutMinimum: amountOutMininum,
                    sqrtPriceLimitX96: 0
                });
            outputAmount = swapRouter.exactInputSingle(params);
        }
        return outputAmount;
    }

    function getTopUpAmount(uint256 tokenId_, address owner_, uint256 usdcAmount_) public view returns(uint256) {
        uint256 topUpAmount;
        uint256 usd24Amount = usdcAmount_.div(FOURDECIMALS);
        if(tokenEligibleForUsdcTopUp(tokenId_) && fiat24account.checkLimit(tokenId_, usd24.convertToChf(usd24Amount))) {
            (,topUpAmount) = usdcAmount_.trySub(calculateFee(tokenId_, owner_, usdcAmount_));
        } else {
            topUpAmount = 0;
        }
        return topUpAmount.div(FOURDECIMALS);
    }

    function calculateFee(uint256 tokenId_, address owner_, uint256 usdcAmount_) public view returns(uint256) {
        uint256 f24Balance = f24.balanceOf(owner_).mul(FOURDECIMALS);
        (,uint256 freeTier) = f24Balance.trySub(getUsedQuota(tokenId_));
        (,uint256 feeTier) = usdcAmount_.trySub(freeTier);
        return feeTier.mul(fee).div(100);
    }

    function getTiers(uint256 tokenId_, address owner_, uint256 usdcAmount_) external view returns(uint256, uint256) {
        uint256 f24Balance = f24.balanceOf(owner_).mul(FOURDECIMALS);
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
        if(tokenEligibleForUsdcTopUp(tokenId_)) {
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
        if(tokenEligibleForUsdcTopUp(tokenId_)) {
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

    function tokenEligibleForUsdcTopUp(uint256 tokenId_) public view returns(bool) {
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

    function addTokenPair(address inputToken, address outputToken) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: Not an operator");
        tokenPairs[keccak256(abi.encodePacked(inputToken, outputToken))] = true;
    }

    function removeTokenPair(address inputToken, address outputToken) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: Not an operator");
        delete tokenPairs[keccak256(abi.encodePacked(inputToken, outputToken))];
    }

    function isTokenPairAvailable(address inputToken, address outputToken) public view returns(bool) {
        return tokenPairs[keccak256(abi.encodePacked(inputToken, outputToken))];
    }

    function changeCryptoDeskAddress(address cryptoDeskAddress_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: Not an operator");
        cryptoDeskAddress = cryptoDeskAddress_;
    }

    function changeTreasuryAdddress(address treasuryAddress_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: Not an operator");
        treasuryAddress = treasuryAddress_;
    }

    function changeFee(uint256 newFee_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: Not an operator");
        fee = newFee_;
    }

    function changeMaxQuota(uint256 maxQuota_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: Not an operator");
        maxQuota = maxQuota_;
    }

    function changeMinTopUpAmount(uint256 minTopUpAmount_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: Not an operator");
        minTopUpAmount = minTopUpAmount_;
    }

    function changeSlippage(uint256 slippage_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: Not an operator");
        slippage = slippage_;
    }

    function setSanctionCheck(bool sanctionCheck_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: Not an operator");
        sanctionCheck = sanctionCheck_;
    }
    
    function setSanctionCheckContract(address sanctionContract_) external {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: Not an operator");
        sanctionContract = sanctionContract_;
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
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: Not an operator");
        _pause();
    }

    function unpause() public {
        require(hasRole(OPERATOR_ROLE, msg.sender), "Fiat24CryptoTopUp: Not an operator");
        _unpause();
    }

    receive() payable external {}
}
