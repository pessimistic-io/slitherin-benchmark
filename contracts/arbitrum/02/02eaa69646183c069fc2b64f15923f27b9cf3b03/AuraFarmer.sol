pragma solidity ^0.8.13;

import "./IERC20.sol";
import "./IVault.sol";
import "./IAuraLocker.sol";
import "./IAuraBalRewardPool.sol";
import "./BalancerAdapter.sol";
import {IL2GatewayRouter} from "./IL2GatewayRouter.sol";
import {AddressAliasHelper} from "./AddressAliasHelper.sol";

interface IAuraBooster {
    function depositAll(uint _pid, bool _stake) external;
    function withdraw(uint _pid, uint _amount) external;
}

contract AuraFarmer is BalancerComposableStablepoolAdapter {

    error ExpansionMaxLossTooHigh();
    error WithdrawMaxLossTooHigh();
    error TakeProfitMaxLossTooHigh();
    error MaxLossHigherThanSetableByGuardian();
    error OnlyL2Chair();
    error OnlyGov();
    error OnlyL2Guardian();
    error NotEnoughTokens();
    error NotEnoughBPT();
    error AuraWithdrawFailed();
    error NothingWithdrawn();
    error OnlyChairCanTakeBPTProfit();
    error NoProfit();
    error GettingRewardFailed();

    IAuraBalRewardPool public dolaBptRewardPool;
    IAuraBooster public booster;
   
    address public l2Chair;
    address public l2Guardian;

    uint public dolaDeposited; // TODO: use this to calculate the amount of DOLA to deposit and if we have profit
    uint public dolaProfit; // TODO: review this variable accounting
    uint public constant pid = 12;
    uint public maxLossExpansionBps;
    uint public maxLossWithdrawBps;
    uint public maxLossTakeProfitBps;
    uint public maxLossSetableByGuardianBps;

    // Actual addresses
    IL2GatewayRouter public immutable l2GatewayRouter = IL2GatewayRouter(0x5288c571Fd7aD117beA99bF60FE0846C4E84F933); 
    IERC20 public immutable DOLAL1 = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    IERC20 public immutable auraL1 = IERC20(0xC0c293ce456fF0ED870ADd98a0828Dd4d2903DBF);
    IERC20 public immutable balL1 = IERC20(0xba100000625a3754423978a60c9317c58a424e3D);

    IERC20 public immutable bal;
    IERC20 public immutable aura = IERC20(0x1509706a6c66CA549ff0cB464de88231DDBe213B);

    address public arbiFedL1;
    address public arbiGovMessengerL1;

    event Deposit(uint amount);
    event Withdraw(uint amount);

     struct InitialAddresses {
        address dola;
        address vault;
        address dolaBptRewardPool;
        address bpt;
        address booster;
        address l2Chair;
        address l2Guardian;
        address arbiFedL1;
        address arbiGovMessengerL1;
    }
    
    constructor(
        InitialAddresses memory addresses_,
        uint maxLossExpansionBps_,
        uint maxLossWithdrawBps_,
        uint maxLossTakeProfitBps_,
        bytes32 poolId_
        ) 
        BalancerComposableStablepoolAdapter(poolId_, addresses_.dola, addresses_.vault, addresses_.bpt)
    {   
        if(maxLossExpansionBps_ >= 10000) revert ExpansionMaxLossTooHigh();
        if(maxLossWithdrawBps_ >= 10000) revert WithdrawMaxLossTooHigh();
        if(maxLossTakeProfitBps_ >= 10000) revert TakeProfitMaxLossTooHigh();
        dolaBptRewardPool = IAuraBalRewardPool(addresses_.dolaBptRewardPool);
        booster = IAuraBooster(addresses_.booster);
        bal = IERC20(dolaBptRewardPool.rewardToken());
        (address bpt,) = IVault(addresses_.vault).getPool(poolId_);
        IERC20(bpt).approve(addresses_.booster, type(uint256).max);
        maxLossExpansionBps = maxLossExpansionBps_;
        maxLossWithdrawBps = maxLossWithdrawBps_;
        maxLossTakeProfitBps = maxLossTakeProfitBps_;
        l2Chair = addresses_.l2Chair;
        l2Guardian = addresses_.l2Guardian;
        arbiFedL1 = addresses_.arbiFedL1;
        arbiGovMessengerL1 = addresses_.arbiGovMessengerL1;
    }

    modifier onlyGov() {
        address callerL1 = AddressAliasHelper.undoL1ToL2Alias(msg.sender);
        if (arbiGovMessengerL1 != callerL1) revert OnlyGov();
        _;
    }

    modifier onlyGuardian() {
        if(l2Guardian != msg.sender){
            address callerL1 = AddressAliasHelper.undoL1ToL2Alias(msg.sender);
            if (arbiGovMessengerL1 != callerL1) revert OnlyL2Guardian();       
        }
        _;
    }

    modifier onlyChair() {
        if(l2Chair != msg.sender) revert OnlyL2Chair();
        _;
    }

    /**
    @notice Method for gov to change the chair
    */
    function changeL2Chair(address newL2Chair) onlyGov external {
        l2Chair = newL2Chair;
    }

    function changeL2Guardian(address newL2Guardian) onlyGov external {
        l2Guardian = newL2Guardian;
    }

    function changeArbiFedL1(address newArbiFedL1) onlyGov external {
        arbiFedL1 = newArbiFedL1;
    }

    function changeArbiGovMessengerL1(address newArbiGovMessengerL1) onlyGov external {
        arbiGovMessengerL1 = newArbiGovMessengerL1;
    }

    /**
    @notice Method for current chair of the Aura Farmer to resign
    */
    function resign() onlyChair external {
        l2Chair = address(0);
    }

    function setMaxLossExpansionBps(uint newMaxLossExpansionBps) onlyGuardian external {
        if(msg.sender == l2Guardian && newMaxLossExpansionBps > maxLossSetableByGuardianBps) revert MaxLossHigherThanSetableByGuardian();
        if(newMaxLossExpansionBps >= 10000) revert ExpansionMaxLossTooHigh();
        maxLossExpansionBps = newMaxLossExpansionBps;
    }

    function setMaxLossWithdrawBps(uint newMaxLossWithdrawBps) onlyGuardian external  {
        if(msg.sender == l2Guardian && newMaxLossWithdrawBps > maxLossSetableByGuardianBps) revert MaxLossHigherThanSetableByGuardian();
        if(newMaxLossWithdrawBps >= 10000) revert WithdrawMaxLossTooHigh();
        maxLossWithdrawBps = newMaxLossWithdrawBps;
    }

    function setMaxLossTakeProfitBps(uint newMaxLossTakeProfitBps) onlyGuardian external {
        if(msg.sender == l2Guardian && newMaxLossTakeProfitBps > maxLossSetableByGuardianBps) revert MaxLossHigherThanSetableByGuardian();
        if(newMaxLossTakeProfitBps >= 10000) revert TakeProfitMaxLossTooHigh();
        maxLossTakeProfitBps = newMaxLossTakeProfitBps;   
    }

    function setMaxLossSetableByGuardianBps(uint newMaxLossSetableByGuardianBps) onlyGov external {
       maxLossSetableByGuardianBps = newMaxLossSetableByGuardianBps; 
    }

    /**
    @notice Deposits amount of dola tokens into balancer, before locking with aura
    @param amount Amount of dola token to deposit
    */
    function deposit(uint amount) onlyChair external {
        dolaDeposited += amount;
        _deposit(amount, maxLossExpansionBps);
        booster.depositAll(pid, true);
        emit Deposit(amount); // Amount of dola deposited into balancer
    }
    /**
    @notice Withdraws an amount of dola token to be burnt, contracting DOLA dolaSupply
    @dev Be careful when setting maxLoss parameter. There will almost always be some loss from
    slippage + trading fees that may be incurred when withdrawing from a Balancer pool.
    On the other hand, setting the maxLoss too high, may cause you to be front run by MEV
    sandwhich bots, making sure your entire maxLoss is incurred.
    Recommended to always broadcast withdrawl transactions(contraction & takeProfits)
    through a frontrun protected RPC like Flashbots RPC.
    @param amountDola The amount of dola tokens to withdraw. Note that more tokens may
    be withdrawn than requested, as price is calculated by debts to strategies, but strategies
    may have outperformed price of dola token.
    */
    function withdrawLiquidity(uint256 amountDola) onlyChair external returns (uint256) {
        //Calculate how many lp tokens are needed to withdraw the dola
        uint256 bptNeeded = bptNeededForDola(amountDola);
        if(bptNeeded > bptSupply()) revert NotEnoughBPT();

        //Withdraw BPT tokens from aura, but don't claim rewards
        if(!dolaBptRewardPool.withdrawAndUnwrap(bptNeeded, false)) revert AuraWithdrawFailed();

        //Withdraw DOLA from balancer pool
        uint256 dolaWithdrawn = _withdraw(amountDola, maxLossWithdrawBps);
        if(dolaWithdrawn == 0) revert NothingWithdrawn();
       
        _updateDolaDeposited(dolaWithdrawn);

        emit Withdraw(dolaWithdrawn);

        return dolaWithdrawn;
    }

    /**
    @notice Withdraws every remaining balLP token. Can take up to maxLossWithdrawBps in loss, compared to dolaSupply.
    It will still be necessary to call takeProfit to withdraw any potential rewards.
    */
    function withdrawAllLiquidity() onlyChair external returns (uint256) {
  
        if(!dolaBptRewardPool.withdrawAndUnwrap(dolaBptRewardPool.balanceOf(address(this)), false)) revert AuraWithdrawFailed();
        uint256 dolaWithdrawn = _withdrawAll(maxLossWithdrawBps);
        if(dolaWithdrawn == 0) revert NothingWithdrawn();

        _updateDolaDeposited(dolaWithdrawn);

        emit Withdraw(dolaWithdrawn);

        return dolaWithdrawn;
    }

    /**
    @notice Withdraws the profit generated by aura staking
    @dev See dev note on Contraction method
    */
    // TODO: review this function and adjust for L2 (review dolaDeposited and dolaProfit logic and edge cases)
    function takeProfit(bool harvestLP) public {
        //This takes balLP at face value, but doesn't take into account slippage or fees
        //Worth considering that the additional transaction fees incurred by withdrawing the small amount of profit generated by tx fees,
        //may not eclipse additional transaction costs. Set harvestLP = false to only withdraw bal and aura rewards.

        uint bptValue = bptSupply() * bpt.getRate() / 10**18;
        if(harvestLP && bptValue > dolaDeposited) {
            if(msg.sender != l2Chair) revert OnlyChairCanTakeBPTProfit();
            uint dolaSurplus = bptValue - dolaDeposited;
            uint bptToWithdraw = bptNeededForDola(dolaSurplus);
            if(bptToWithdraw > dolaBptRewardPool.balanceOf(address(this))){
                bptToWithdraw = dolaBptRewardPool.balanceOf(address(this));
            }
            if(!dolaBptRewardPool.withdrawAndUnwrap(bptToWithdraw, false)) revert AuraWithdrawFailed();
            uint dolaProfit_ = _withdraw(dolaSurplus, maxLossTakeProfitBps);
            if(dolaProfit_ == 0) revert NoProfit();
            dolaProfit += dolaProfit_;
        }

        if(!dolaBptRewardPool.getReward(address(this), true)) revert GettingRewardFailed();
    }
    
    // Bridiging back to L1 TODO: review this bridging code
    /**
    @notice Withdraws `dolaAmount` of DOLA to arbiFed on L1. Will take 7 days before withdraw is claimable on L1.
    */
    function withdrawToL1ArbiFed(uint dolaAmount) external onlyChair {
        if (dolaAmount > dola.balanceOf(address(this))) revert NotEnoughTokens();

        bytes memory empty;
        l2GatewayRouter.outboundTransfer(address(DOLAL1), arbiFedL1, dolaAmount, empty);
    }

        /**
    @notice Withdraws `amount` of `l2Token` to address `to` on L1. Will take 7 days before withdraw is claimable.
    */
    function withdrawTokensToL1(address l1Token,address l2Token, address to, uint amount) external onlyChair {
        if (amount > IERC20(l2Token).balanceOf(address(this))) revert NotEnoughTokens();
        bytes memory empty;
        l2GatewayRouter.outboundTransfer(address(l1Token), to, amount, empty);
    }

    /**
    @notice View function for getting bpt tokens in the contract + aura dolaBptRewardPool
    */
    function bptSupply() public view returns(uint){
        return IERC20(bpt).balanceOf(address(this)) + dolaBptRewardPool.balanceOf(address(this));
    }

    function _updateDolaDeposited(uint dolaWithdrawn) internal {   
       if(dolaWithdrawn >= dolaDeposited) {
            dolaDeposited = 0;
            dolaProfit += dolaWithdrawn - dolaDeposited;
        } else {
            dolaDeposited -= dolaWithdrawn;
        }
    }
}

