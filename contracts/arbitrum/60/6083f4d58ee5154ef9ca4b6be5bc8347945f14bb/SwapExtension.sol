//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;


import "./LibStorage.sol";
import "./SwapTypes.sol";
import "./LibConstants.sol";
import "./IRevshareVault.sol";
import "./LibFees.sol";

import "./IERC20.sol";
import "./SafeERC20.sol";

import "./console.sol";

/**
 * Dexible will eventually support multiple types of executions. The swap logic is handled 
 * by this extension library that handles checking for swap details and calling routers
 * with specified input.
 */
library SwapExtension {
    using SafeERC20 for IERC20;

    event SwapFailed(address indexed trader, 
                     IERC20 feeToken, 
                     uint gasFeePaid);
    event SwapSuccess(address indexed trader,
                        address indexed affiliate,
                        uint inputAmount,
                        uint outputAmount,
                        IERC20 feeToken,
                        uint gasFee,
                        uint affiliateFee,
                        uint dexibleFee);
    event AffiliatePaid(address indexed affiliate, IERC20 token, uint amount);
    event PaidGasFunds(address indexed relay, uint amount);
    event InsufficientGasFunds(address indexed relay, uint amount);

    /**
     * NOTE: These gas settings are used to estmate the total gas being used
     * to execute a transaction. Because solidity provides no way to determine
     * the actual gas used until the txn is mined, we have to add buffer gas 
     * amount to account for post-gas-fee computation logic.
     */

    

    //final computation needed to compute and transfer gas fees
    uint constant POST_OP_GAS = 80_000;

    struct SwapDetails {
        bool feeIsInput;
        bool isSelfSwap;
        uint startGas;
        uint toProtocol;
        uint toRevshare;
        uint outToTrader;
        uint outAmount;
        uint bpsAmount;
        uint gasAmount;
        uint nativeGasAmount;
        uint preDXBLBalance;
        uint remainingInBalance;
    }

    function fill(SwapTypes.SwapRequest calldata request, SwapDetails memory details) public returns (SwapDetails memory) {
        preCheck(request, details);
        details.outAmount = request.tokenOut.token.balanceOf(address(this));
        preFill(request);

        for(uint i=0;i<request.routes.length;++i) {
            SwapTypes.RouterRequest calldata rr = request.routes[i];
            IERC20(rr.routeAmount.token).safeApprove(rr.spender, rr.routeAmount.amount);
            (bool s, ) = rr.router.call(rr.routerData);

            if(!s) {
                revert("Failed to swap");
            }
        }
        uint out = request.tokenOut.token.balanceOf(address(this));
        if(details.outAmount < out) {
            details.outAmount = out - details.outAmount;
        } else {
            details.outAmount = 0;
        }
        
        console.log("Expected", request.tokenOut.amount, "Received", details.outAmount);
        //first, make sure enough output was generated
        require(details.outAmount >= request.tokenOut.amount, "Insufficient output generated");
        return details;
    }

    function postFill(SwapTypes.SwapRequest calldata request, SwapDetails memory details, bool success) public  {

        //get post-swap balance so we know how much refund if we didn't spend all
        uint cBal = request.tokenIn.token.balanceOf(address(this));

        //deliberately setting remaining balance to 0 if less amount than current balance.
        //this will force an underflow exception if we attempt to deduct more fees than
        //remaining balance
        details.remainingInBalance = cBal > details.remainingInBalance ? cBal - details.remainingInBalance : 0;

        console.log("Remaining input balance", details.remainingInBalance);

        if(success) {
            //if we succeeded, then do successful post-swap ops
            handleSwapSuccess(request, details); 
        }  else {
            //otherwise, handle as a failure
            handleSwapFailure(request, details);
        }
        //console.log("Total gas use for relay payment", totalGasUsed);
        //pay the relayer their gas fee if we have funds for it
        payRelayGas(details.nativeGasAmount);
    }

    /**
     * When a relay-based swap fails, we need to account for failure gas fees if the input
     * token is the fee token. That's what this function does
     */
    function handleSwapFailure(SwapTypes.SwapRequest calldata request, SwapDetails memory details) public {
        //compute fees for failed txn
        if(details.isSelfSwap) {
            revert("Swap failed");
        }
        
        //trader still owes the gas fees to the treasury/relay even though the swap failed. This is because
        //the trader may have set slippage too low, or other problems thus increasing the chance of failure.
        
        //compute gas fee in fee-token units
        unchecked { 
            //the total gas used thus far plus some post-op stuff that needs to get done
            uint totalGas = (details.startGas - gasleft()) + 40000;
            
            console.log("Estimated gas used for trader gas payment", totalGas);
            details.nativeGasAmount = (totalGas * tx.gasprice);
        }
        uint gasInFeeToken = LibFees.computeGasFee(request, details.nativeGasAmount);
        if(details.feeIsInput) {
            console.log("Transferring partial input token to devteam for failure gas fees");
            
            console.log("Failed gas fee", gasInFeeToken);

            //transfer input assets to treasury
            request.executionRequest.fee.feeToken.safeTransferFrom(request.executionRequest.requester, LibStorage.getDexibleStorage().treasury, gasInFeeToken);
            
            emit SwapFailed(request.executionRequest.requester, request.executionRequest.fee.feeToken, gasInFeeToken);
        } else {
            //otherwise, if not the input token, unfortunately, Dexible treasury eats the cost.
            console.log("Fee token is output; therefore cannot reimburse team for failure gas fees");
            emit SwapFailed(request.executionRequest.requester, request.executionRequest.fee.feeToken, 0);
        }
    }

    /**
     * This is called when a relay-based swap is successful. It basically rewards DXBL tokens
     * to trader and pays appropriate fees.
     */
    function handleSwapSuccess(SwapTypes.SwapRequest calldata request, 
                SwapDetails memory details) public {
        
        
        //reward trader with DXBL tokens
        collectDXBL(request, details.feeIsInput, details.outAmount);

        //pay fees
        payAndDistribute(request, details);
    }

    /**
     * Reward DXBL to the trader
     */
    function collectDXBL(SwapTypes.SwapRequest memory request, bool feeIsInput, uint outAmount) public {
        uint value = 0;
        if(feeIsInput) {
            //when input, the total input amount is used to determine reward rate
            value = request.tokenIn.amount;
        } else {
            //otherwise, it's the output generated from the swap
            value = outAmount;
        }
        //Dexible is the only one allowed to ask the vault to mint tokens on behalf of a trader
        //See RevshareVault for logic of minting rewards
        IRevshareVault(LibStorage.getDexibleStorage().revshareManager).rewardTrader(request.executionRequest.requester, address(request.executionRequest.fee.feeToken), value);
    }

    /**
     * Distribute payments to revshare pool, affiliates, treasury, and trader
     */
    function payAndDistribute(SwapTypes.SwapRequest memory request, 
                                SwapDetails memory details) public  {
        payRevshareAndAffiliate(request, details);
        payProtocolAndTrader(request, details);
    }

    /**
     * Payout bps portions to revshare pool and affiliate
     */
    function payRevshareAndAffiliate(SwapTypes.SwapRequest memory request, 
                                SwapDetails memory details) public {
        //assume trader gets all output
        details.outToTrader = details.outAmount;

        //the bps portion of fee. 
        details.bpsAmount = LibFees.computeBpsFee(request, details.feeIsInput, details.preDXBLBalance, details.outAmount);
    
        //console.log("Total bps fee", payments.bpsAmount);
        uint minFee = LibFees.computeMinFeeUnits(address(request.executionRequest.fee.feeToken));
        if(minFee > details.bpsAmount) {
            console.log("Trade too small. Charging minimum flat fee", minFee);
            details.bpsAmount = minFee;
        }

        //revshare pool gets portion of bps fee collected
        details.toRevshare = (details.bpsAmount * LibStorage.getDexibleStorage().revshareSplitRatio) / 100;

        console.log("To revshare", details.toRevshare);

        //protocol gets remaining bps but affiliate fees come out of its portion. This could revert if
        //Dexible miscalculated the affiliate reward portion. However, the call would revert here and
        //Dexible relay would pay the gas fee.
        details.toProtocol = (details.bpsAmount-details.toRevshare) - request.executionRequest.fee.affiliatePortion;

        console.log("Protocol pre-gas", details.toProtocol);

        //fees accounted for thus far
        uint total = details.toRevshare + details.toProtocol + request.executionRequest.fee.affiliatePortion;
            
        if(!details.feeIsInput) {
            //this is an interim calculation. Gas fees get deducted later as well. This will
            //also revert if insufficient output was generated to cover all fees
            console.log("Out amount", details.outAmount, "Total fees so far", total);
            require(details.outAmount > total, "Insufficient output to pay fees");
            details.outToTrader = details.outAmount - total;
        } else {
            //this will revert with error if total is more than we have available
            //forcing caller to pay gas for insufficient buffer in input amount vs. traded amount
            require(details.remainingInBalance > total, "Insufficient input funds to pay fees");
            details.remainingInBalance -= total;
        }

        //now distribute fees
        IERC20 feeToken = request.executionRequest.fee.feeToken;
        //pay revshare their portion
        feeToken.safeTransfer(LibStorage.getDexibleStorage().revshareManager, details.toRevshare);
        if(request.executionRequest.fee.affiliatePortion > 0) {
            //pay affiliate their portion
            feeToken.safeTransfer(request.executionRequest.fee.affiliate, request.executionRequest.fee.affiliatePortion);
            emit AffiliatePaid(request.executionRequest.fee.affiliate, feeToken, request.executionRequest.fee.affiliatePortion);
        }
    }

    /**
     * Final step to compute gas consumption for trader and pay the protocol and trader 
     * their shares.
     */
    function payProtocolAndTrader(SwapTypes.SwapRequest memory request,
                            SwapDetails memory details) public {
        
        if(!details.isSelfSwap) {
            //If this was a relay-based swap, we need to pay treasury an estimated gas fee
            

            //we leave unguarded for gas savings since we know start gas is always higher 
            //than used and will never rollover without costing an extremely large amount of $$
            unchecked { 
                console.log("Start gas", details.startGas, "Left", gasleft());

                //the total gas used thus far plus some post-op buffer for transfers and events
                uint totalGas = (details.startGas - gasleft()) + POST_OP_GAS;
                
                console.log("Estimated gas used for trader gas payment", totalGas);
                details.nativeGasAmount = (totalGas * tx.gasprice);
            }
            //use price oracle in vault to get native price in fee token
            details.gasAmount = LibFees.computeGasFee(request, details.nativeGasAmount);
            console.log("Gas paid by trader in fee token", details.gasAmount);

            //add gas payment to treasury portion
            details.toProtocol += details.gasAmount;
            console.log("Payment to protocol", details.toProtocol);

            if(!details.feeIsInput) {
                //if output was fee, deduct gas payment from proceeds
                require(details.outToTrader >= details.gasAmount, "Insufficient output to pay gas fees");
                details.outToTrader -= details.gasAmount;
            } else {
                //will revert if insufficient remaining balance to cover gas causing caller
                //to pay all gas and get nothing if they don't have sufficient buffer of input vs
                //router input amount
                require(details.remainingInBalance >= details.gasAmount, "Insufficient input to pay gas fees");
                details.remainingInBalance -= details.gasAmount;
            }
            //console.log("Proceeds to trader", payments.outToTrader);
        }

        //now distribute fees
        IERC20 feeToken = request.executionRequest.fee.feeToken;
        feeToken.safeTransfer(LibStorage.getDexibleStorage().treasury, details.toProtocol);

        //console.log("Sending total output to trader", payments.outToTrader);
        request.tokenOut.token.safeTransfer(request.executionRequest.requester, details.outToTrader);
        
        //refund any remaining over-estimate of input amount needed
        if(details.remainingInBalance > 0) {
            //console.log("Total refund to trader", payments.remainingInBalance);
            request.tokenIn.token.safeTransfer(request.executionRequest.requester, details.remainingInBalance);
        }   
        emit SwapSuccess(request.executionRequest.requester,
                    request.executionRequest.fee.affiliate,
                    request.tokenOut.amount,
                    details.outToTrader, 
                    request.executionRequest.fee.feeToken,
                    details.gasAmount,
                    request.executionRequest.fee.affiliatePortion,
                    details.bpsAmount); 
        //console.log("Finished swap");
    }

    function preCheck(SwapTypes.SwapRequest calldata request, SwapDetails memory details) public view {
        //make sure fee token is allowed
        address fToken = address(request.executionRequest.fee.feeToken);
        bool ok = IRevshareVault(LibStorage.getDexibleStorage()
                .revshareManager).isFeeTokenAllowed(fToken);
        require(
            ok, 
            "Fee token is not allowed"
        );

        //and that it's one of the tokens swapped
        require(fToken == address(request.tokenIn.token) ||
                fToken == address(request.tokenOut.token), 
                "Fee token must be input or output token");

         //get the current DXBL balance at the start to apply discounts
        details.preDXBLBalance = LibStorage.getDexibleStorage().dxblToken.balanceOf(request.executionRequest.requester);
        
        //flag whether the input token is the fee token
        details.feeIsInput = address(request.tokenIn.token) == address(request.executionRequest.fee.feeToken);
        if(details.feeIsInput) {
            //if it is make sure it doesn't match the first router input amount to account for fees.
            require(request.tokenIn.amount > request.routes[0].routeAmount.amount, "Input fee token amount does not account for fees");
        }

        //get the starting input balance for the input token so we know how much was spent for the swap
        details.remainingInBalance = request.tokenIn.token.balanceOf(address(this));
    }

    function preFill(SwapTypes.SwapRequest calldata request) public {
        //transfer input tokens to router so it can perform dex trades
        console.log("Transfering input for trading:", request.tokenIn.amount);
        //we transfer the entire input, not the router-only inputs. This is to 
        //save gas on individual transfers. Any unused portion of input is returned 
        //to the trader in the end.
        request.tokenIn.token.safeTransferFrom(request.executionRequest.requester, address(this), request.tokenIn.amount);
        console.log("Expected output", request.tokenOut.amount);
    }


    /**
     * Pay the relay with gas funds stored in this contract. The gas used provided 
     * does not include arbitrum multiplier but may include additional amount for post-op
     * gas estimates.
     */
    function payRelayGas(uint gasFee) public {
        
        console.log("Relay Gas Reimbursement", gasFee);
        //if there is ETH in the contract, reimburse the relay that called the fill function
        if(address(this).balance < gasFee) {
            console.log("Cannot reimburse relay since do not have enough funds");
            emit InsufficientGasFunds(msg.sender, gasFee);
        } else {
            console.log("Transfering gas fee to relay");
            payable(msg.sender).transfer(gasFee);
            emit PaidGasFunds(msg.sender, gasFee);
        }
    }

    
}
