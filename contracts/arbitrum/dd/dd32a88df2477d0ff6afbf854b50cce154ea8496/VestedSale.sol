// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./Sale.sol";
import "./VestingToken.sol";
import "./IERC20Metadata.sol";
import "./SafeERC20.sol";
import "./Errors.sol";

contract VestedSale is Sale {
    using SafeERC20 for IERC20Metadata;

    // Currently planned vesting levels are listed below.
    // No enum is used to allow creators increase number of vesting schedules
    // and extend the sale with more batches
    // 0 - TEAM,
    // 1 - ROUND A
    // 2 - ROUND B

    /**
     * @dev Divider to calculate percentage of the vest releases from BPS
     */
    uint256 constant BPS_DIVIDER = 10_000;

    /**
     * @dev A vesting plan definition
     *
     * @param cliff Cliff timeline - meaning when funds will start to get released
     * @param vestingPeriod Number of seconds vesting will proceed after ther cliff date
     * @param dayOneRelease Percentage of tokens released right at the cliff date to the users
     */
    struct VestingPlan {
        uint256 cliff; // Number of days until linear release of funds
        uint256 vestingPeriod; // Number of seconds vesting will last from cliff till the end
        uint256 dayOneRelease; // Percentage (in 0.01 units) released on day one - excluded from vesting
    }

    /**
     * @dev The event emitted on token withdrawal by the investor
     *
     * @param investor Investor address that withdraws tokens
     * @param amount Amount of tokens withdrawn
     */
    event Withdrawn(address indexed investor, uint256 amount);

    /**
     * @dev The event emitted on bulk deposit made by the owner
     *
     * @param plan The sale plan for all deposits made in bulk
     */
    event BulkDepositMade(uint256 indexed plan);

    /**
     * A mapping between sale plans (key) to vesting it is connected to (value)
     */
    mapping(uint256 => uint256) vestingMapping;

    /**
     * An array of all vesting plans configured in the contract
     */
    // slither-disable-next-line similar-names
    VestingPlan[] public vestingPlans;

    /**
     * A special vested coin contracts rewards with all users upon deposits 1-1 the token
     * released on the withdrawal
     */
    VestingToken public immutable vestingToken;

    /**
     * The token address
     */
    IERC20Metadata immutable coin;

    /**
     * @dev The constructor of the contract
     *
     * @param owner_ Owner address for the contract
     * @param vault_ The vault all funds from sales will be passed to
     * @param coin_ The coin that is being sold
     * @param salePlans_ All plans preconfigured with contract creation
     * @param vestingMappings_ Mappings which sale plans are connected to which vesting plans
     * @param vestingPlans_ All vesting plans preconfigured with contract creation
     */
    constructor(
        address owner_,
        address payable vault_,
        IERC20Metadata coin_,
        SalePlanConfiguration[] memory salePlans_,
        uint256[] memory vestingMappings_,
        VestingPlan[] memory vestingPlans_
    ) Sale(owner_, vault_, salePlans_) {
        vestingToken = new VestingToken();

        coin = coin_;
        for (uint256 i = 0; i < vestingPlans_.length;) {
            vestingPlans.push(vestingPlans_[i]);
            unchecked {
                ++i;
            }
        }

        for (uint256 i = 0; i < vestingMappings_.length;) {
            vestingMapping[i] = vestingMappings_[i];
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Return all vesting plans configurations
     */
    function getAllVestingPlans() external view returns (VestingPlan[] memory) {
        return vestingPlans;
    }

    /**
     * @dev Adds new sale plan (with vesting plan) to the list.
     *
     * @param salePlan_ New sale plan to add
     * @param vestingPlan_ New vesting plan that is connected to the sale plan
     */
    function addNewPlans(SalePlanConfiguration calldata salePlan_, VestingPlan calldata vestingPlan_)
        public
        onlyOwner
    {
        addNewSalePlan(salePlan_, false);
        vestingPlans.push(vestingPlan_);
        vestingMapping[salePlans.length - 1] = vestingPlans.length - 1;
    }

    /**
     * @dev Method to perform the sale by making deposit in other token
     *
     * @param plan_ The plan deposit is made to
     * @param amount_ Amount of token offered
     * @param token_ Token address the purchase is made with. 0 - if native currency is used.
     */
    function deposit(uint256 plan_, uint256 amount_, address token_) external payable {
        uint256 reward = _deposit(plan_, amount_, token_);
        vestingToken.mint(_msgSender(), reward);
        _retrieveFunds(_msgSender(), token_, amount_);
    }

    /**
     * @dev Method allowing the owner to upload a bulk list of deposits made outside of the
     * contract to keep track of its vestings.
     *
     * Reminder: bulkDeposit omits all caps set as global or user-based. Use with caution.
     *
     * @param salePlan_ Sale plan for the bulk upload
     * @param receivers_ An array of the receiver addresses for the bulk upload
     * @param timestamps_ An array of timestamps to set as the deposits vesting start time.
     * @param amounts_ An array of amounts of bulk deposits
     */
    function bulkDeposit(
        uint256 salePlan_,
        address[] calldata receivers_,
        uint256[] calldata timestamps_,
        uint256[] calldata amounts_
    ) external onlyOwner {
        // slither-disable-next-line timestamp
        if (salePlans[salePlan_].endTime <= block.timestamp) revert Timeout();
        emit BulkDepositMade(salePlan_);

        for (uint256 i = 0; i < receivers_.length;) {
            // slither-disable-start reentrancy-no-eth
            // slither-disable-start calls-loop
            vestingToken.mint(receivers_[i], amounts_[i]);
            _internalDeposit(salePlan_, receivers_[i], amounts_[i], timestamps_[i]);
            // slither-disable-end calls-loop
            // slither-disable-end reentrancy-no-eth
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @dev Withdrawal method for vested deposits owners. Automatically calculate
     * and returns user all tokens released by vesting plans so far.
     */
    function withdraw() external notSuspended {
        uint256 to_claim;
        for (uint256 i = 0; i < salePlans.length;) {
            uint256 claimable = _withdrawableFromDeposit(i, _msgSender());
            deposits[i][_msgSender()].withdrawn += claimable;
            to_claim += claimable;
            unchecked {
                ++i;
            }
        }
        emit Withdrawn(_msgSender(), to_claim);
        // slither-disable-next-line incorrect-equality
        if (to_claim == 0) revert NothingToClaim();
        // slither-disable-next-line timestamp
        if (vestingToken.balanceOf(_msgSender()) < to_claim) revert MissingVestingTokens();
        // slither-disable-next-line reentrancy-events
        vestingToken.burn(_msgSender(), to_claim);

        coin.safeTransfer(_msgSender(), to_claim);
    }

    /**
     * @dev Method to calculate how much given invester has unclaimed and unvested funds in the system
     * at given moment.
     *
     * @param investor_ The investor address to calculate funds for.
     *
     * @return The amount of unclaimed and unvested tokens that can be withdrawn.
     */
    function availableForWithdraw(address investor_) public view returns (uint256) {
        uint256 amount;
        for (uint256 i = 0; i < salePlans.length;) {
            amount += _withdrawableFromDeposit(i, investor_);
            unchecked {
                ++i;
            }
        }
        return amount;
    }

    /**
     * @dev Method to calculate how much given invester has unclaimed and unvested funds in the system
     * at given moment.
     *
     * @param investor_ The investor address to calculate funds for.
     * @param plan_ The sale plan to be checked
     *
     * @return The amount of unclaimed and unvested tokens that can be withdrawn.
     */
    function availableForWithdrawInPlan(address investor_, uint256 plan_) public view returns (uint256) {
        return _withdrawableFromDeposit(plan_, investor_);
    }

    /**
     * @dev Overriden implementation to inform about decimal places for sale reward calculations
     * of the sold coin
     */
    function _decimals(uint256) internal virtual override returns (uint256) {
        return coin.decimals();
    }

    /**
     * @dev Internal withdrawal calculator for a single deposit.
     *
     * @param depositIndex_ Index of checked deposit
     * @param investor_ Investor address deposit is assigned to
     *
     * @return Withdrawable amount
     */
    function _withdrawableFromDeposit(uint256 depositIndex_, address investor_) internal view returns (uint256) {
        Deposit storage dep = deposits[depositIndex_][investor_];
        if (dep.amount == 0) return 0;
        VestingPlan storage vest = vestingPlans[vestingMapping[depositIndex_]];
        uint256 cliff = dep.time + vest.cliff;
        // slither-disable-next-line timestamp
        if (block.timestamp >= cliff) {
            // slither-disable-next-line timestamp
            if (block.timestamp > cliff + vest.vestingPeriod) {
                return dep.amount - dep.withdrawn;
            } else {
                uint256 day_one_release = (vest.dayOneRelease * dep.amount) / BPS_DIVIDER;
                uint256 amount_to_release = dep.amount - day_one_release;

                // slither-disable-next-line timestamp
                uint256 seconds_elapsed = block.timestamp - cliff;
                uint256 calc_amount = day_one_release + ((amount_to_release * seconds_elapsed) / vest.vestingPeriod);
                return calc_amount - dep.withdrawn;
            }
        }
        return 0;
    }
}

