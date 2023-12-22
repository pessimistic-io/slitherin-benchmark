pragma solidity 0.8.7;

import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";

contract Staking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    // 30 day, 6% APR; 60 days, 12% APR
    uint256[] public lockupPeriods = [30 days, 60 days];
    uint256[] public multipliers = [100, 200];
    uint256 public constant BASE_APR = 6; // represent in percent
    bool public allowStaking = true;

    address public immutable SPA;
    address public immutable rewardAccount;
    uint256 public immutable endTime;

    uint256 public totalStakedSPA;
    mapping(address => bool) public isRewardFrozen; // track if a user's reward is frozen due to malicious attempts

    struct DepositProof {
        uint256 amount;
        uint256 liability;
        uint256 startTime;
        uint256 expiryTime;
    }
    mapping(address => DepositProof[]) balances;

    /// Events
    event Staked(
        address indexed account,
        uint256 amount,
        uint256 totalStakedSPA
    );
    event Withdrawn(
        address indexed account,
        uint256 amount,
        uint256 totalStakedSPA
    );
    event WithdrawnWithPenalty(
        address indexed account,
        uint256 amount,
        uint256 totalStakedSPA
    );
    event RewardFrozen(address indexed account, bool status);
    event StakingEnabled(bool status);

    /**
     * @param _SPA Address of SPA contract
     * @param _rewardAccount Address of reward account
     * @param _endTime Time in seconds
     */
    constructor(
        address _SPA,
        address _rewardAccount,
        uint256 _endTime
    ) {
        assert(lockupPeriods.length == multipliers.length);
        require(_endTime != 0, "_endTime is zero");
        require(_SPA != address(0), "_SPA is zero address");
        require(_rewardAccount != address(0), "_rewardAccount is zero address");
        SPA = _SPA;
        rewardAccount = _rewardAccount;
        endTime = block.timestamp + _endTime;
    }

    /**
     * @dev get number of deposits for an account
     */
    function getNumDeposits(address account) external view returns (uint256) {
        return balances[account].length;
    }

    /**
     * @dev get N-th deposit for an account
     */
    function getDeposits(address account, uint256 index)
        external
        view
        returns (DepositProof memory)
    {
        return balances[account][index];
    }

    function getLiability(
        uint256 deposit,
        uint256 multiplier,
        uint256 lockupPeriod
    ) public view returns (uint256) {
        // calc liability
        return
            (deposit * BASE_APR * multiplier * lockupPeriod) /
            (1 days) /
            (100 * 100 * 365); // remember to div by 100 // remember to div by 100
    }

    function setRewardFrozen(address account, bool status) external onlyOwner {
        isRewardFrozen[account] = status;
        emit RewardFrozen(account, status);
    }

    /**
     * @dev allow owner to enable and disable staking.
     */
    function toggleStaking() external onlyOwner {
        allowStaking = !allowStaking;
        emit StakingEnabled(allowStaking);
    }

    function stake(uint256 amount, uint256 lockPeriod) external nonReentrant {
        require(amount > 0, "cannot stake 0"); // don't allow staking 0

        // check if staking is enabled
        require(allowStaking, "staking is disabled");

        // check whether lockTime passed the endTime or not
        require(
            block.timestamp + lockPeriod < endTime,
            "lockTime has passed endTime"
        );

        address account = _msgSender();
        uint256 multiplier = 0;
        for (uint256 i = 0; i < lockupPeriods.length; i++) {
            if (lockPeriod == lockupPeriods[i]) {
                multiplier = multipliers[i];
                break;
            }
        }
        require(multiplier > 0, "invalid lock period");

        uint256 liability = getLiability(amount, multiplier, lockPeriod);
        require(
            IERC20(SPA).balanceOf(rewardAccount) >= liability,
            "insufficient budget"
        );

        DepositProof memory deposit = DepositProof({
            amount: amount,
            liability: liability,
            startTime: block.timestamp,
            expiryTime: block.timestamp + lockPeriod
        });
        balances[account].push(deposit);

        totalStakedSPA += deposit.amount;

        // Transferring the spa amount from User -> contract
        IERC20(SPA).safeTransferFrom(account, address(this), amount);
        // Locking the liability amount in the contract
        IERC20(SPA).safeTransferFrom(rewardAccount, address(this), liability);

        emit Staked(account, amount, totalStakedSPA);
    }

    function withdraw(uint256 index) external nonReentrant {
        address account = _msgSender();
        require(index < balances[account].length, "invalid account or index");
        DepositProof memory deposit = balances[account][index];
        require(deposit.expiryTime <= block.timestamp, "not expired");

        // destroy deposit by:
        // replacing index with last one, and pop out the last element
        uint256 last = balances[account].length;
        balances[account][index] = balances[account][last - 1];
        balances[account].pop();

        totalStakedSPA -= deposit.amount;

        if (!isRewardFrozen[account]) {
            uint256 withdrawAmount = deposit.liability + deposit.amount;
            // Transfer the amount and reward to account
            IERC20(SPA).safeTransfer(account, withdrawAmount);
            emit Withdrawn(account, withdrawAmount, totalStakedSPA);
        } else {
            // user forfeits reward and reward is sent to reward pool
            IERC20(SPA).safeTransfer(rewardAccount, deposit.liability);
            IERC20(SPA).safeTransfer(account, deposit.amount);
            emit WithdrawnWithPenalty(account, deposit.amount, totalStakedSPA);
        }
    }
}

