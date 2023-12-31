// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

/**
@title Yearn Harvest
@author yearn.finance
@notice Yearn Harvest or yHarvest is a smart contract that leverages Gelato to automate
the harvest of strategies that have yHarvest assigned as its keeper.
The contract provides the Gelato network of keepers Yearn harvest jobs that
are ready to execute, and it pays Gelato after a succesful harvest. The contract detects 
when a new stragegy is using it as its keeper and creates a Gelato job automatically.
@dev We use Lens to detect new strategies, but Lens does not include strategies that are
not in a vault's withdrawal queue. This is not expected all the time, but it can happen and
has happened.
*/

import {SafeMath} from "./SafeMath.sol";
import {Address} from "./Address.sol";
import {SafeERC20, IERC20} from "./SafeERC20.sol";
import {StrategyAPI, VaultAPI, StrategyParams} from "./BaseStrategy.sol";
import {IGelatoOps} from "./IGelato.sol";

/**
@title Yearn Lens Interface
@notice We leverage the Yearn Lens set of contracts to obtain an up-to-date
snapshot of active strategies in production.
 */
interface IYearnLens {
    function assetsStrategiesAddresses()
        external
        view
        returns (address[] memory);
}

contract YearnHarvest {
    using Address for address;
    using SafeMath for uint256;

    // `jobIds` keeps track of the Gelato job IDs for each strategy and
    // the yHarvest contract.
    mapping(address => bytes32) public jobIds;

    // `feeToken` is the crypto used for payment.
    address internal constant feeToken =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    // `maxFee` determines the max fee allowed to be paid to Gelato
    // denominated in `feeToken`. Note that setting it to 0 would
    // effectively prevent all executors from running any task.
    // To change its value, call `setMaxFee()`
    uint256 public maxFee = 1e16;

    // Yearn Lens data lens
    IYearnLens internal immutable lens;

    // Gelato Ops Proxy contract
    IGelatoOps internal immutable ops;

    // Yearn accounts
    address public owner;
    address payable public governance;
    address payable public pendingGovernance;

    // Yearn modifiers
    modifier onlyKeepers() {
        require(
            msg.sender == owner ||
                msg.sender == governance ||
                msg.sender == address(ops),
            "!keeper"
        );
        _;
    }

    modifier onlyAuthorized() {
        require(msg.sender == owner || msg.sender == governance, "!authorized");
        _;
    }

    modifier onlyGovernance() {
        require(msg.sender == governance, "!governance");
        _;
    }

    // `HarvestedByGelato` is an event we emit when there's a succesful harvest
    event HarvestedByGelato(bytes32 jobId, address strategy, uint256 gelatoFee);

    constructor(address _lens, address _gelatoOps) public {
        // Set owner and governance
        owner = msg.sender;
        governance = msg.sender;

        // Set Yearn Lens address
        lens = IYearnLens(_lens);

        // Set Gelato Ops Proxy
        ops = IGelatoOps(_gelatoOps);
    }

    /**
    @notice Create Gelato job that will monitor for new strategies in Yearn Lens. When
    a new startegy is detected with its keeper set as yHarvest, yHarvest creates a
    gelato job for it. 
    */
    function initiateStrategyMonitor() external onlyAuthorized {
        jobIds[address(this)] = ops.createTaskNoPrepayment(
            address(this), // `execAddress`
            this.createHarvestJob.selector, // `execSelector`
            address(this), // `resolverAddress`
            abi.encodeWithSelector(this.checkNewStrategies.selector),
            feeToken
        );
    }

    /**
    @notice Creates Gelato job for a strategy. Updates `jobIds`, which we use to log 
    events and to manage the job.
    @param strategyAddress Strategy Address for which a harvest job will be created
    */
    function createHarvestJob(address strategyAddress) external onlyKeepers {
        // Create job and add it to the Gelato registry
        createJob(strategyAddress);

        // `gelatoFee` and `gelatoFeeToken` are state variables in the gelato ops contract that
        // are temporarily modified by the executors right before executing the payload. They are
        // reverted to default values when the gelato contract exec() method wraps up.
        (uint256 gelatoFee, address gelatoFeeToken) = ops.getFeeDetails();

        require(gelatoFeeToken == feeToken, "!token"); // dev: gelato not using intended token
        require(gelatoFee <= maxFee, "!fee"); // dev: gelato executor overcharnging for the tx

        // Pay Gelato for the service.
        payKeeper(gelatoFee);
    }

    /**
    @notice Creates Gelato job for a strategy. The difference with the function above is that
    this function can be used to manually create a job. The function above is used by Gelato
    to create a harvest job when a new strategy is identified in an automated fashion. A manual
    creation of a harvest job might be needed, for example, if we have to manually cancel a job
    and re-start it afterwards. 
    @param strategyAddress Strategy Address for which a job will be created
    */
    function createJob(address strategyAddress) public onlyKeepers {
        jobIds[strategyAddress] = ops.createTaskNoPrepayment(
            address(this), // `execAddress`
            this.harvestStrategy.selector, // `execSelector`
            address(this), // `resolverAddress`
            abi.encodeWithSelector(
                this.checkHarvestStatus.selector,
                strategyAddress
            ),
            feeToken
        );
    }

    /**
    @notice Cancel a Gelato job given a strategy address
    @dev cancelJob(address(this)) cancels the strategy monitor job
    @param strategyAddress Strategy for which to cancel a job
    */
    function cancelJob(address strategyAddress) external onlyAuthorized {
        ops.cancelTask(jobIds[strategyAddress]); // dev: reverts if non-existent
        delete jobIds[strategyAddress];
    }

    /**
    @notice Used by keepers to determine whether a new strategy was added to Yearn Lens
    that has the yHarvest contract as its keeper. 
    @return canExec boolean indicating whether a new strategy requires automation.
    @return execPayload call data used by Gelato executors to call createHarvestJob(). It
    includes the address of the strategy to harvest as an input.
    */
    function checkNewStrategies()
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        execPayload = bytes("No new strategies to automate");

        // Pull list of active strategies in production
        address[] memory strategies = lens.assetsStrategiesAddresses();

        // Check if there are strategies with yHarvest assigned as keeper
        for (uint256 i = 0; i < strategies.length; i++) {
            if (StrategyAPI(strategies[i]).keeper() != address(this)) {
                continue;
            }
            // Skip if there's an active job already created for the strategy
            if (jobIds[strategies[i]] == 0) {
                canExec = true;
                execPayload = abi.encodeWithSelector(
                    this.createHarvestJob.selector,
                    strategies[i]
                );
                break;
            }
        }
    }

    /**
    @notice Used by keepers to check whether a strategy is ready to harvest. 
    @param strategyAddress Strategy for which to obtain a harvest status
    @return canExec boolean indicating whether the strategy is ready to harvest
    @return execPayload call data used by Gelato executors to call harvestStrategy(). It
    includes the address of the strategy to harvest as an input parameter.
    */
    function checkHarvestStatus(address strategyAddress)
        external
        view
        returns (bool canExec, bytes memory execPayload)
    {
        execPayload = bytes("Strategy not ready to harvest");

        // Declare a strategy object
        StrategyAPI strategy = StrategyAPI(strategyAddress);

        // Make sure yHarvest remains the keeper of the strategy.
        if (strategy.keeper() != address(this)) {
            if (jobIds[strategyAddress] == 0) {
                execPayload = bytes("Strategy was never onboarded to yHarvest");
            } else {
                execPayload = bytes("Strategy no longer automated by yHarvest");
            }
            return (canExec, execPayload);
        }

        // `callCostInWei` is a required input to the `harvestTrigger()` method of the strategy
        // and represents the expected cost to call `harvest()`. Some blockchains have global
        // variables/functions such as block.basefee or gasUsed() that allow us to estimate the
        // cost to harvest. Not all do, so for now we pass a common, low, fixed cost accross
        // strategies so that the trigger focuses on all other conditions.

        // call the harvest trigger
        canExec = strategy.harvestTrigger(uint256(1e8));

        // If we can execute, prepare the payload
        if (canExec) {
            execPayload = abi.encodeWithSelector(
                this.harvestStrategy.selector,
                strategyAddress
            );
        }
    }

    /**
    @notice Function that Gelato keepers call to harvest a strategy after `checkHarvestStatus()`
    has confirmed that it's ready to harvest.
    It checks that the executors are getting paid in the expected crytocurrency and that
    they do not overcharge for the tx. The method also pays executors.
    @dev an active job for a strategy linked to the yHarvest must exist for executors to be
    able to call this function. 
    @param strategyAddress The address of the strategy to harvest
    */
    function harvestStrategy(address strategyAddress) public onlyKeepers {
        // Declare a strategy object
        StrategyAPI strategy = StrategyAPI(strategyAddress);

        // `gelatoFee` and `gelatoFeeToken` are state variables in the gelato contract that
        // are temporarily modified by the executors before executing the payload. They are
        // reverted to default values when the gelato contract exec() method wraps up.
        (uint256 gelatoFee, address gelatoFeeToken) = ops.getFeeDetails();

        require(gelatoFeeToken == feeToken, "!token"); // dev: gelato not using intended token
        require(gelatoFee <= maxFee, "!fee"); // dev: gelato executor overcharnging for the tx

        // Re-run harvestTrigger() with the gelatoFee passed by the executor to ensure
        // the tx makes economic sense.
        require(strategy.harvestTrigger(gelatoFee), "!economic");

        strategy.harvest();

        // Pay Gelato for the service.
        payKeeper(gelatoFee);

        emit HarvestedByGelato(
            jobIds[strategyAddress],
            strategyAddress,
            gelatoFee
        );
    }

    /**
    @notice Pays Gelato keepers.
    @param gelatoFee Fee amount to pay Gelato keepers. Determined by the keeper.
    */
    function payKeeper(uint256 gelatoFee) internal {
        address payable gelato = ops.gelato();

        (bool success, ) = gelato.call{value: gelatoFee}("");
        require(success, "!payment");
    }

    /**
    @notice Sets the max fee we allow Gelato to charge for a harvest
    @dev Setting `maxFee` would effectively stop all jobs as they 
    would all start reverting.
    @param _maxFee Max fee we allow Gelato to charge for a harvest.
    */
    function setMaxFee(uint256 _maxFee) external onlyAuthorized {
        maxFee = _maxFee;
    }

    /**
    @notice Changes the `owner` address.
    @param _owner The new address to assign as `owner`.
    */
    function setOwner(address _owner) external onlyAuthorized {
        require(_owner != address(0));
        owner = _owner;
    }

    // 2-phase commit for a change in governance
    /**
    @notice
    Nominate a new address to use as governance.

    The change does not go into effect immediately. This function sets a
    pending change, and the governance address is not updated until
    the proposed governance address has accepted the responsibility.

    @param _governance The address requested to take over yHarvest governance.
    */
    function setGovernance(address payable _governance)
        external
        onlyGovernance
    {
        pendingGovernance = _governance;
    }

    /**
    @notice
    Once a new governance address has been proposed using setGovernance(),
    this function may be called by the proposed address to accept the
    responsibility of taking over governance for this contract.

    This may only be called by the proposed governance address.
    @dev
    setGovernance() should be called by the existing governance address,
    prior to calling this function.
    */
    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "!authorized");
        governance = pendingGovernance;
        delete pendingGovernance;
    }

    /**
    @notice Allows governance to transfer funds out of the contract
    @param _token The address of the token, which balance is to be transfered
    to the governance multisig.
    */
    function sweep(address _token) external onlyGovernance {
        uint256 amount;
        if (_token == feeToken) {
            amount = address(this).balance;
            (bool success, ) = governance.call{value: amount}("");
            require(success, "!transfer");
        } else {
            amount = IERC20(_token).balanceOf(address(this));
            SafeERC20.safeTransfer(IERC20(_token), governance, amount);
        }
    }

    // enables the contract to receive native crypto
    receive() external payable {}
}

