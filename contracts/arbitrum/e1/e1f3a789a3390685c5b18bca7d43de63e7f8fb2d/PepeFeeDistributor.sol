//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable } from "./Ownable.sol";
import { IERC20 } from "./IERC20.sol";
import { IPepeFeeDistributor } from "./IPepeFeeDistributor.sol";

contract PepeFeeDistributor is IPepeFeeDistributor, Ownable {
    /**
     * @dev Assume the 3 contracts as stakers in a pool. The pool is the feeDistributor contract that'd receive fees from pepeBet(pool rewards).
     * @dev The rewards will come in streams, whenever a bet is placed and the pool will allocate rewards to the stakers based on their share of the pool.
     * @dev Let's assume the share of the stakers are 60%, 30% and 10% respectively.
     * @dev In bps, the share of the stakers are 6_000, 3_000 and 1_000 respectively with a total pool amount of 10_000.
     * @dev the total stake amount of 10_000 will never change.
     */

    ///@dev 60% goes to the pls accumulator address.
    ///@dev 30% goes to the lock contract
    ///@dev 10% goes to staking contract

    uint16 public constant BPS_DIVISOR = 10_000; ///@dev basis points divisor. Also acts as the total staked in this contract.
    IERC20 public immutable usdcToken;

    address public stakingContract; ///@dev staking contract where users can stake $PEG to receive 10% of protocol fees as $USDC rewards.
    address public lockContract; ///@dev lock contract where users can lock for 6 months $PEG to receive 30% of protocol fees as $USDC rewards.
    address public plsAccumulationContract; ///@dev pls accumulation wallet that will buy and accumulate $PLS.
    uint256 public accumulatedUsdcPerContract; ///@dev usdc allocated to the three contracts in the fee distributor.
    uint256 public lastBalance; ///@dev last balance of usdc this contract (fee distributor).
    uint48 public lastUpdatedTimestamp; ///@dev last time the fee distributor rewards were updated.
    uint16 public stakeShare = 1_000; ///@dev share of fees allocated to the staking contract.
    uint16 public lockShare = 3_000; ///@dev share of fees allocated to the lock contract.
    uint16 public plsAccumulationShare = 6_000; ///@dev share of fees allocated to the pls accumulation contract.

    mapping(address => int256) public shareDebt; ///@dev share debt of each contract.

    event FeeDistributed(uint256 indexed toStaking, uint256 indexed toLock, uint256 indexed toPlsAccumulation);
    event UpdatedContracts(
        address indexed stakingContract,
        address indexed lockContract,
        address indexed plsAccumulationContract
    );

    constructor(address _usdcToken, address _stakingContract, address _lockContract, address _plsAccumulationContract) {
        require(_usdcToken != address(0), "!_usdcToken");
        require(_stakingContract != address(0), "!_stakingContract");
        require(_lockContract != address(0), "!_lockContract");
        require(_plsAccumulationContract != address(0), "!_plsAccumulationContract");

        usdcToken = IERC20(_usdcToken);
        stakingContract = _stakingContract;
        lockContract = _lockContract;
        plsAccumulationContract = _plsAccumulationContract;
    }

    ///@dev based on the amount of usdc we received after the last update, we update the accumulatedUsdcPerContract.
    function updateAllocations() public override {
        if (uint48(block.timestamp) > lastUpdatedTimestamp) {
            uint256 contractBalance = usdcToken.balanceOf(address(this));
            uint256 diff = contractBalance - lastBalance;
            if (diff != 0) {
                accumulatedUsdcPerContract += diff / BPS_DIVISOR; //1usdc comes in. 1_000_000 / 10_000 = 100
            }
            lastUpdatedTimestamp = uint48(block.timestamp);
        }
    }

    ///@dev allocate rewards to the staking contract.
    function allocateStake() public override returns (uint256) {
        updateAllocations();
        int256 accumulatedStakingUsdc = int256(stakeShare * accumulatedUsdcPerContract); //1_000 * 100 = 100_000 (0.1usdc)
        uint256 pendingStakingUsdc = uint256(accumulatedStakingUsdc - shareDebt[stakingContract]); // initial shareDebt is 0 so pendingStakingUsdc = 100_000
        if (pendingStakingUsdc != 0) {
            shareDebt[stakingContract] = accumulatedStakingUsdc;
            lastBalance = usdcToken.balanceOf(address(this)) - pendingStakingUsdc;

            require(usdcToken.transfer(stakingContract, pendingStakingUsdc), "transfer failed");
            emit FeeDistributed(pendingStakingUsdc, 0, 0);
        }
        return pendingStakingUsdc;
    }

    ///@dev allocate rewards to the lock contract.
    function allocateLock() public override returns (uint256) {
        updateAllocations();
        int256 accumulatedLockUsdc = int256(lockShare * accumulatedUsdcPerContract); //3_000 * 100 = 300_000 (0.3 usdc)
        uint256 pendingLockUsdc = uint256(accumulatedLockUsdc - shareDebt[lockContract]); // initial shareDebt is 0 so pendingLockUsdc = 300_000
        if (pendingLockUsdc != 0) {
            shareDebt[lockContract] = accumulatedLockUsdc;
            lastBalance = usdcToken.balanceOf(address(this)) - pendingLockUsdc;
            require(usdcToken.transfer(lockContract, pendingLockUsdc), "transfer failed");
            emit FeeDistributed(0, pendingLockUsdc, 0);
        }
        return pendingLockUsdc;
    }

    ///@dev allocate rewards to the pls accumulation contract.
    function allocatePlsAccumulation() public override returns (uint256) {
        updateAllocations();
        int256 accumulatedPlsAccUsdc = int256(plsAccumulationShare * accumulatedUsdcPerContract); //6_000 * 100 = 600_000 (0.6 usdc)
        uint256 pendingPlsAccUsdc = uint256(accumulatedPlsAccUsdc - shareDebt[plsAccumulationContract]); // initial shareDebt is 0 so pendingPlsAccUsdc = 600_000
        if (pendingPlsAccUsdc != 0) {
            shareDebt[plsAccumulationContract] = accumulatedPlsAccUsdc;
            lastBalance = usdcToken.balanceOf(address(this)) - pendingPlsAccUsdc;
            require(usdcToken.transfer(plsAccumulationContract, pendingPlsAccUsdc), "transfer failed");
            emit FeeDistributed(0, 0, pendingPlsAccUsdc);
        }
        return pendingPlsAccUsdc;
    }

    ///@dev This function allows us to allocate rewards to all three contracts at once, updating the allocations just once.
    function allocateToAll() public override {
        updateAllocations();

        int256 accumulatedStakingUsdc = int256(stakeShare * accumulatedUsdcPerContract);
        uint256 pendingStakingUsdc = uint256(accumulatedStakingUsdc - shareDebt[stakingContract]);

        int256 accumulatedLockUsdc = int256(lockShare * accumulatedUsdcPerContract);
        uint256 pendingLockUsdc = uint256(accumulatedLockUsdc - shareDebt[lockContract]);

        int256 accumulatedPlsAccUsdc = int256(plsAccumulationShare * accumulatedUsdcPerContract);
        uint256 pendingPlsAccUsdc = uint256(accumulatedPlsAccUsdc - shareDebt[plsAccumulationContract]);

        if (pendingStakingUsdc != 0) {
            shareDebt[stakingContract] = accumulatedStakingUsdc;
            lastBalance = usdcToken.balanceOf(address(this)) - pendingStakingUsdc;
            require(usdcToken.transfer(stakingContract, pendingStakingUsdc), "transfer failed");
        }
        if (pendingLockUsdc != 0) {
            shareDebt[lockContract] = accumulatedLockUsdc;
            lastBalance = usdcToken.balanceOf(address(this)) - pendingLockUsdc;
            require(usdcToken.transfer(lockContract, pendingLockUsdc), "transfer failed");
        }
        if (pendingPlsAccUsdc != 0) {
            shareDebt[plsAccumulationContract] = accumulatedPlsAccUsdc;
            lastBalance = usdcToken.balanceOf(address(this)) - pendingPlsAccUsdc;
            require(usdcToken.transfer(plsAccumulationContract, pendingPlsAccUsdc), "transfer failed");
        }

        emit FeeDistributed(pendingStakingUsdc, pendingLockUsdc, pendingPlsAccUsdc);
    }

    ///@param _stakingContract the address of the new staking contract. Pass in address(0) to keep the current staking contract.
    ///@param _lockContract the address of the new lock contract. Pass in address(0) to keep the current lock contract.
    ///@param _plsAccumulationContract the address of the new plsAccumulation contract. Pass in address(0) to keep the current plsAccumulation contract.
    function updateContractAddresses(
        address _stakingContract,
        address _lockContract,
        address _plsAccumulationContract
    ) external override onlyOwner {
        if (_stakingContract != address(0)) {
            stakingContract = _stakingContract;
        }
        if (_lockContract != address(0)) {
            lockContract = _lockContract;
        }
        if (_plsAccumulationContract != address(0)) {
            plsAccumulationContract = _plsAccumulationContract;
        }

        emit UpdatedContracts(stakingContract, lockContract, plsAccumulationContract);
    }

    ///@param _stakeShare the new share of the staking contract. Must be less than or equal to BPS_DIVISOR.
    ///@param _lockShare the new share of the lock contract. Must be less than or equal to BPS_DIVISOR.
    ///@param _plsAccumulationShare the new share of the plsAccumulation contract. Must be less than or equal to BPS_DIVISOR.
    function updateContractShares(
        uint16 _stakeShare,
        uint16 _lockShare,
        uint16 _plsAccumulationShare
    ) external override onlyOwner {
        require(_stakeShare + _lockShare + _plsAccumulationShare == BPS_DIVISOR, "invalid shares");
        allocateToAll(); //essential to allocate to all in one timestamp before changing shares

        stakeShare = _stakeShare;
        shareDebt[stakingContract] = int256(_stakeShare * accumulatedUsdcPerContract);

        lockShare = _lockShare;
        shareDebt[lockContract] = int256(_lockShare * accumulatedUsdcPerContract);

        plsAccumulationShare = _plsAccumulationShare;
        shareDebt[plsAccumulationContract] = int256(_plsAccumulationShare * accumulatedUsdcPerContract);
    }

    function getShareDebt(address _contract) external view override returns (int256) {
        return shareDebt[_contract];
    }

    function getContractShares() external view override returns (uint16, uint16, uint16) {
        return (stakeShare, lockShare, plsAccumulationShare);
    }

    function getContractAddresses() external view override returns (address, address, address) {
        return (stakingContract, lockContract, plsAccumulationContract);
    }

    function getLastBalance() external view override returns (uint256) {
        return lastBalance;
    }

    function getAccumulatedUsdcPerContract() external view override returns (uint256) {
        return accumulatedUsdcPerContract;
    }

    function getLastUpdatedTimestamp() external view override returns (uint48) {
        return lastUpdatedTimestamp;
    }
}

