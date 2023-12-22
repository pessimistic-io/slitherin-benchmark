//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./ConfigurableDexible.sol";
import "./LibStorage.sol";
import "./SwapExtension.sol";

/**
 * Dexible is the core contract used by the protocol to execution various actions. Swapping,
 * heding, staking, etc. are all handled through the Dexible contract. The contract is also
 * coupled to the RevshareVault in that only this contract can request that tokens be rewarded
 * to users.
 */
contract Dexible is ConfigurableDexible {

    //used for trycatch calls
    modifier onlySelf() {
        require(msg.sender == address(this), "Internal call only");
        _;
    }
    using SwapExtension for SwapTypes.SwapRequest;
    using LibDexible for LibDexible.DexibleStorage;
    using SafeERC20 for IERC20;


    /**
     * Initialize Dexible with config settings. This can only be called once after
     * deployment.
     */
    function initialize(LibDexible.DexibleConfig calldata config) public {
        //initialize dexible storage settings
        LibDexible.initialize(LibStorage.getDexibleStorage(), config);

        //initialize key roles
        LibRoleManagement.initializeRoles(LibStorage.getRoleStorage(), config.roleManager);

        //initialize multi-sig settings
        super.initializeMSConfigurable(config.multiSigConfig);
    }

    /**
     * Set the treasury to send share of revenue and gas fees after approval and timeout
     */
    function setTreasury(address t) external override afterApproval(this.setTreasury.selector) {
        LibDexible.DexibleStorage storage ds = LibStorage.getDexibleStorage();
        require(t != address(0), "Invalid treasury address");
        ds.treasury = t;
    }

    /**
     * Main swap function that is only callable by Dexible relays. This version of swap 
     * accounts for affiliate rewards and discounts.
     */
    function swap(SwapTypes.SwapRequest calldata request) external onlyRelay notPaused {
        //console.log("----------------------------- START SWAP ------------------------");
       
        //compute how much gas we have at the outset, plus some gas for loading contract, etc.
        uint startGas = gasleft() + LibConstants.PRE_OP_GAS;
        SwapExtension.SwapDetails memory details = SwapExtension.SwapDetails({
            feeIsInput: false,
            isSelfSwap: false,
            startGas: startGas,
            bpsAmount: 0,
            gasAmount: 0,
            nativeGasAmount: 0,
            toProtocol: 0,
            toRevshare: 0,
            outToTrader: 0,
            preDXBLBalance: 0,
            outAmount: 0,
            remainingInBalance: 0
        });

        bool success = false;
        //execute the swap but catch any problem
        try this._trySwap{
            gas: gasleft() - LibConstants.POST_OP_GAS
        }(request, details) returns (SwapExtension.SwapDetails memory sd) {
            details = sd;
            success = true;
        } catch {
            console.log("Swap failed");
            success = false;
        }

        request.postFill(details, success);
        //console.log("----------------------------- END SWAP ------------------------");
        
    }

    /**
     * This version of swap can be called by anyone. The caller becomes the trader
     * and they pay all gas fees themselves. This is needed to prevent sybil attacks
     * where traders can provide their own affiliate address and get discounts.
     */
    function selfSwap(SwapTypes.SelfSwap calldata request) external notPaused {
        //we create a swap request that has no affiliate attached and thus no
        //automatic discount.
        SwapTypes.SwapRequest memory swapReq = SwapTypes.SwapRequest({
            executionRequest: ExecutionTypes.ExecutionRequest({
                fee: ExecutionTypes.FeeDetails({
                    feeToken: request.feeToken,
                    affiliate: address(0),
                    affiliatePortion: 0
                }),
                requester: msg.sender
            }),
            tokenIn: request.tokenIn,
            tokenOut: request.tokenOut,
            routes: request.routes
        });
        SwapExtension.SwapDetails memory details = SwapExtension.SwapDetails({
            feeIsInput: false,
            isSelfSwap: true,
            startGas: 0,
            bpsAmount: 0,
            gasAmount: 0,
            nativeGasAmount: 0,
            toProtocol: 0,
            toRevshare: 0,
            outToTrader: 0,
            preDXBLBalance: 0,
            outAmount: 0,
            remainingInBalance: 0
        });
        details = swapReq.fill(details);
        swapReq.postFill(details, true);
    }

    function _trySwap(SwapTypes.SwapRequest memory request, SwapExtension.SwapDetails memory details) external onlySelf returns (SwapExtension.SwapDetails memory) {
        return request.fill(details);
    }

}
