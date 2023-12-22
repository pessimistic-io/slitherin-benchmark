// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
pragma experimental ABIEncoderV2;

import "./MathUtil.sol";
import "./IStakingProxy.sol";
import "./IRewardStaking.sol";
import "./BoringMath.sol";
import "./QLqdr.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Math.sol";
import "./OwnableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import {IAxelarGateway} from "./IAxelarGateway.sol";
import {IAxelarExecutable} from "./IAxelarExecutable.sol";
import {IAxelarGasService} from "./IAxelarGasService.sol";

/*
LQDR Locking cross chain gateway contract
*/
contract QLqdrGateway is ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using BoringMath for uint256;
    using BoringMath224 for uint224;
    using BoringMath112 for uint112;
    using BoringMath32 for uint32;
    using SafeERC20 for IERC20;

    /* ========== AXELAR VARIABLES ========== */
    IAxelarGasService public gasService;
    IAxelarGateway public gateway;
    error InvalidAddress();
    error NotApprovedByGateway();
    bytes32 internal LOCK;
    bytes32 internal CHECKPOINT_EPOCH;
    bytes32 internal WITHDRAW_EXPIRED_LOCKS_TO;
    bytes32 internal PROCESS_EXPIRED_LOCKS;
    bytes32 internal KICK_EXPIRED_LOCKS;

    /* ========== STATE VARIABLES ========== */

    struct Balances {
        uint112 locked;
        uint32 nextUnlockIndex;
    }
    struct LockedBalance {
        uint112 amount;
        uint32 unlockTime;
    }
    struct Epoch {
        uint224 supply; //epoch supply
        uint32 date; //epoch start date
    }

    // Duration that rewards are streamed over
    uint256 public rewardsDuration;

    // Duration of lock/earned penalty period
    uint256 public lockDuration;

    //supplies and epochs
    uint256[] public lockedSupply;
    // Epoch[] public epochs;
    mapping(uint256 => Epoch[]) public epochs;

    //mappings for balance data
    mapping(address => mapping(uint256 => Balances)) public balances;
    mapping(address => mapping(uint256 => LockedBalance[])) public userLocks;

    uint256 public denominator;

    //management
    uint256 public kickRewardPerEpoch;
    uint256 public kickRewardEpochDelay;

    mapping(string => bool) private chainWhitelisted;
    mapping(string => bool) private sourceWhitelisted;
    mapping(string => uint256) private chainIds;
    mapping(uint256 => string) private chains;
    mapping(uint256 => string) private gateways;

    uint256 public chainsLength;

    //shutdown
    bool public isShutdown;

    QLqdr public qLqdr;

    /* ========== CONSTRUCTOR ========== */

    constructor() {}

    function initialize(
        address payable _qLqdr,
        uint256 _rewardsDuration,
        address gateway_,
        address gasReceiver_
    ) public initializer {
        if (gateway_ == address(0)) revert InvalidAddress();
        gateway = IAxelarGateway(gateway_);
        if (gasReceiver_ == address(0)) revert InvalidAddress();
        gasService = IAxelarGasService(gasReceiver_);
        LOCK = keccak256("lock");
        CHECKPOINT_EPOCH = keccak256("checkpointEpoch");
        WITHDRAW_EXPIRED_LOCKS_TO = keccak256("withdrawExpiredLocksTo");
        PROCESS_EXPIRED_LOCKS = keccak256("processExpiredLocks");
        KICK_EXPIRED_LOCKS = keccak256("kickExpiredLocks");

        require(_qLqdr != address(0), "Zero address");
        qLqdr = QLqdr(_qLqdr);

        __Ownable_init();
        __ReentrancyGuard_init();

        denominator = 10000;
        kickRewardPerEpoch = 100;
        kickRewardEpochDelay = 4;

        rewardsDuration = _rewardsDuration;
        lockDuration = rewardsDuration * 16;

        isShutdown = false;
    }

    /* ========== AXELAR GATEWAY CONFIGURATION ========== */
    modifier onlySelf() {
        require(
            msg.sender == address(this),
            "Function must be called by the same contract only"
        );
        _;
    }

    modifier onlyQLqdr() {
        require(
            msg.sender == address(qLqdr),
            "Function must be called by the QLqdr contract only"
        );
        _;
    }

    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external {
        bytes32 payloadHash = keccak256(payload);

        if (
            !gateway.validateContractCall(
                commandId,
                sourceChain,
                sourceAddress,
                payloadHash
            )
        ) revert NotApprovedByGateway();

        _execute(sourceChain, sourceAddress, payload);
    }

    function executeWithToken(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) external {
        bytes32 payloadHash = keccak256(payload);

        if (
            !gateway.validateContractCallAndMint(
                commandId,
                sourceChain,
                sourceAddress,
                payloadHash,
                tokenSymbol,
                amount
            )
        ) revert NotApprovedByGateway();

        _executeWithToken(
            sourceChain,
            sourceAddress,
            payload,
            tokenSymbol,
            amount
        );
    }

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal {
        (bytes memory functionName, bytes memory params) = abi.decode(
            payload,
            (bytes, bytes)
        );
        bytes4 commandSelector;

        require(chainWhitelisted[sourceChain], "Chain not whitelisted");
        require(sourceWhitelisted[sourceAddress], "Source not whitelisted");
        uint256 _chainId = chainIds[sourceChain];

        bool success;
        bytes memory result;

        if (keccak256(functionName) == LOCK) {
            commandSelector = QLqdrGateway.lock.selector;
            (success, result) = address(this).call(
                abi.encodeWithSelector(commandSelector, params, _chainId)
            );
        } else if (keccak256(functionName) == CHECKPOINT_EPOCH) {
            commandSelector = QLqdrGateway.checkpointEpoch.selector;
            (success, result) = address(this).call(
                abi.encodeWithSelector(commandSelector, _chainId)
            );
        } else if (keccak256(functionName) == WITHDRAW_EXPIRED_LOCKS_TO) {
            commandSelector = QLqdrGateway.withdrawExpiredLocksTo.selector;
            (success, result) = address(this).call(
                abi.encodeWithSelector(commandSelector, params, _chainId)
            );
        } else if (keccak256(functionName) == PROCESS_EXPIRED_LOCKS) {
            commandSelector = QLqdrGateway.processExpiredLocks.selector;
            (success, result) = address(this).call(
                abi.encodeWithSelector(commandSelector, params, _chainId)
            );
        } else if (keccak256(functionName) == KICK_EXPIRED_LOCKS) {
            commandSelector = QLqdrGateway.kickExpiredLocks.selector;
            (success, result) = address(this).call(
                abi.encodeWithSelector(commandSelector, params, _chainId)
            );
        } else {
            revert("Invalid function name");
        }

        // shouln't revert in production or tokens could be stuck
        if (!success) {
            if (result.length == 0) {
                require(success, "Failed with no reason");
            } else {
                // rethrow same error
                assembly {
                    let start := add(result, 0x20)
                    let end := add(result, mload(result))
                    revert(start, end)
                }
            }
        }
    }

    function _executeWithToken(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) internal {}

    /* ========== ADMIN CONFIGURATION ========== */

    //set kick incentive
    function setKickIncentive(
        uint256 _rate,
        uint256 _delay
    ) external onlyOwner {
        require(_rate <= 500, "over max rate"); //max 5% per epoch
        require(_delay >= 2, "min delay"); //minimum 2 epochs of grace
        kickRewardPerEpoch = _rate;
        kickRewardEpochDelay = _delay;
    }

    function addChain(
        string memory _chainName,
        string memory _sourceAddress
    ) external onlyOwner {
        chainIds[_chainName] = chainsLength;
        chainWhitelisted[_chainName] = true;
        chains[chainsLength] = _chainName;
        uint256 currentEpoch = block.timestamp.div(rewardsDuration).mul(
            rewardsDuration
        );
        epochs[chainsLength].push(
            Epoch({supply: 0, date: uint32(currentEpoch)})
        );
        sourceWhitelisted[_sourceAddress] = true;
        gateways[chainsLength] = _sourceAddress;
        chainsLength++;
    }

    //shutdown the contract. unstake all tokens. release all locks
    function shutdown() external onlyOwner {
        isShutdown = true;
    }

    /* ========== VIEWS ========== */

    function getSourceWhitelisted(
        string calldata sourceAddress
    ) external view returns (bool) {
        return sourceWhitelisted[sourceAddress];
    }

    function getChainWhitelisted(
        string calldata chainAddress
    ) external view returns (bool) {
        return chainWhitelisted[chainAddress];
    }

    // total token balance of an account, including unlocked but not withdrawn tokens
    function lockedBalanceOf(
        address _user
    ) external view returns (uint256 amount) {
        uint256 i;
        if (address(qLqdr) != address(0)) {
            amount = qLqdr.lockedBalanceOf(_user);
        }
        for (i = 0; i < chainsLength; i++) {
            amount += balances[_user][i].locked;
        }

        return amount;
    }

    //balance of an account which only includes properly locked tokens as of the most recent eligible epoch
    function balanceOf(address _user) external view returns (uint256 amount) {
        if (address(qLqdr) != address(0)) {
            amount = qLqdr.balanceOf(_user);
        }

        for (uint j = 0; j < chainsLength; j++) {
            LockedBalance[] storage locks = userLocks[_user][j];
            Balances storage userBalance = balances[_user][j];
            uint256 nextUnlockIndex = userBalance.nextUnlockIndex;

            //start with current locked amount
            amount += balances[_user][j].locked;

            uint256 locksLength = locks.length;
            //remove old records only (will be better gas-wise than adding up)
            for (uint i = nextUnlockIndex; i < locksLength; i++) {
                if (locks[i].unlockTime <= block.timestamp) {
                    amount = amount.sub(locks[i].amount);
                } else {
                    //stop now as no futher checks are needed
                    break;
                }
            }

            //also remove amount locked in the next epoch
            uint256 currentEpoch = block.timestamp.div(rewardsDuration).mul(
                rewardsDuration
            );
            if (
                locksLength > 0 &&
                uint256(locks[locksLength - 1].unlockTime).sub(lockDuration) >
                currentEpoch
            ) {
                amount = amount.sub(locks[locksLength - 1].amount);
            }
        }

        return amount;
    }

    //balance of an account which only includes properly locked tokens at the given epoch
    function balanceAtEpochOf(
        uint256 _epoch,
        address _user
    ) external view returns (uint256 amount) {
        if (address(qLqdr) != address(0)) {
            amount = qLqdr.balanceAtEpochOf(_epoch, _user);
        }

        for (uint j = 0; j < chainsLength; j++) {
            LockedBalance[] storage locks = userLocks[_user][j];

            //get timestamp of given epoch index
            uint256 epochTime = epochs[j][_epoch].date;
            //get timestamp of first non-inclusive epoch
            uint256 cutoffEpoch = epochTime.sub(lockDuration);

            //need to add up since the range could be in the middle somewhere
            //traverse inversely to make more current queries more gas efficient
            for (uint i = locks.length - 1; i + 1 != 0; i--) {
                uint256 lockEpoch = uint256(locks[i].unlockTime).sub(
                    lockDuration
                );
                //lock epoch must be less or equal to the epoch we're basing from.
                if (lockEpoch <= epochTime) {
                    if (lockEpoch > cutoffEpoch) {
                        amount = amount.add(locks[i].amount);
                    } else {
                        //stop now as no futher checks matter
                        break;
                    }
                }
            }
        }

        return amount;
    }

    //return currently locked but not active balance
    function pendingLockOf(
        address _user,
        uint256 _chainId
    ) external view returns (uint256 amount) {
        LockedBalance[] storage locks = userLocks[_user][_chainId];

        uint256 locksLength = locks.length;

        //return amount if latest lock is in the future
        uint256 currentEpoch = block.timestamp.div(rewardsDuration).mul(
            rewardsDuration
        );
        if (
            locksLength > 0 &&
            uint256(locks[locksLength - 1].unlockTime).sub(lockDuration) >
            currentEpoch
        ) {
            return locks[locksLength - 1].amount;
        }

        return 0;
    }

    function pendingLockAtEpochOf(
        uint256 _epoch,
        address _user,
        uint256 _chainId
    ) external view returns (uint256 amount) {
        LockedBalance[] storage locks = userLocks[_user][_chainId];

        //get next epoch from the given epoch index
        uint256 nextEpoch = uint256(epochs[_chainId][_epoch].date).add(
            rewardsDuration
        );

        //traverse inversely to make more current queries more gas efficient
        for (uint i = locks.length - 1; i + 1 != 0; i--) {
            uint256 lockEpoch = uint256(locks[i].unlockTime).sub(lockDuration);

            //return the next epoch balance
            if (lockEpoch == nextEpoch) {
                return locks[i].amount;
            } else if (lockEpoch < nextEpoch) {
                //no need to check anymore
                break;
            }
        }

        return 0;
    }

    //supply of all properly locked balances at most recent eligible epoch
    function totalSupply() external view returns (uint256 supply) {
        if (address(qLqdr) != address(0)) {
            supply = qLqdr.totalSupply();
        }

        for (uint j = 0; j < chainsLength; j++) {
            uint256 currentEpoch = block.timestamp.div(rewardsDuration).mul(
                rewardsDuration
            );
            uint256 cutoffEpoch = currentEpoch.sub(lockDuration);
            uint256 epochindex = epochs[j].length;

            //do not include next epoch's supply
            if (uint256(epochs[j][epochindex - 1].date) > currentEpoch) {
                epochindex--;
            }

            //traverse inversely to make more current queries more gas efficient
            for (uint i = epochindex - 1; i + 1 != 0; i--) {
                Epoch storage e = epochs[j][i];
                if (uint256(e.date) <= cutoffEpoch) {
                    break;
                }
                supply = supply.add(e.supply);
            }
        }

        return supply;
    }

    //supply of all properly locked balances at the given epoch
    function totalSupplyAtEpoch(
        uint256 _epoch
    ) external view returns (uint256 supply) {
        if (address(qLqdr) != address(0)) {
            supply = qLqdr.totalSupplyAtEpoch(_epoch);
        }

        for (uint j = 0; j < chainsLength; j++) {
            uint256 epochStart = uint256(epochs[j][_epoch].date)
                .div(rewardsDuration)
                .mul(rewardsDuration);
            uint256 cutoffEpoch = epochStart.sub(lockDuration);

            //traverse inversely to make more current queries more gas efficient
            for (uint i = _epoch; i + 1 != 0; i--) {
                Epoch storage e = epochs[j][i];
                if (uint256(e.date) <= cutoffEpoch) {
                    break;
                }
                supply = supply.add(epochs[j][i].supply);
            }
        }

        return supply;
    }

    //find an epoch index based on timestamp
    function findEpochId(
        uint256 _time,
        uint256 _chainId
    ) external view returns (uint256 epoch) {
        uint256 max = epochs[_chainId].length - 1;
        uint256 min = 0;

        //convert to start point
        _time = _time.div(rewardsDuration).mul(rewardsDuration);

        for (uint256 i = 0; i < 128; i++) {
            if (min >= max) break;

            uint256 mid = (min + max + 1) / 2;
            uint256 midEpochBlock = epochs[_chainId][mid].date;
            if (midEpochBlock == _time) {
                //found
                return mid;
            } else if (midEpochBlock < _time) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return min;
    }

    // Information on a user's locked balances
    function lockedBalances(
        address _user,
        uint256 _chainId
    )
        external
        view
        returns (
            uint256 total,
            uint256 unlockable,
            uint256 locked,
            LockedBalance[] memory lockData
        )
    {
        LockedBalance[] storage locks = userLocks[_user][_chainId];
        Balances storage userBalance = balances[_user][_chainId];
        uint256 nextUnlockIndex = userBalance.nextUnlockIndex;
        uint256 idx;
        for (uint i = nextUnlockIndex; i < locks.length; i++) {
            if (locks[i].unlockTime > block.timestamp) {
                if (idx == 0) {
                    lockData = new LockedBalance[](locks.length - i);
                }
                lockData[idx] = locks[i];
                idx++;
                locked = locked.add(locks[i].amount);
            } else {
                unlockable = unlockable.add(locks[i].amount);
            }
        }
        return (userBalance.locked, unlockable, locked, lockData);
    }

    //number of epochs
    function epochCount(uint256 _chainId) external view returns (uint256) {
        return epochs[_chainId].length;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function checkpointEpoch(uint256 _chainId) external {
        _checkpointEpoch(_chainId);
    }

    //insert a new epoch if needed. fill in any gaps
    function _checkpointEpoch(uint256 _chainId) internal {
        //create new epoch in the future where new non-active locks will lock to
        uint256 nextEpoch = block
            .timestamp
            .div(rewardsDuration)
            .mul(rewardsDuration)
            .add(rewardsDuration);
        uint256 epochindex = epochs[_chainId].length;

        //first epoch add in constructor, no need to check 0 length

        //check to add
        if (epochs[_chainId][epochindex - 1].date < nextEpoch) {
            //fill any epoch gaps
            while (
                epochs[_chainId][epochs[_chainId].length - 1].date != nextEpoch
            ) {
                uint256 nextEpochDate = uint256(
                    epochs[_chainId][epochs[_chainId].length - 1].date
                ).add(rewardsDuration);
                epochs[_chainId].push(
                    Epoch({supply: 0, date: uint32(nextEpochDate)})
                );
            }
        }
    }

    // Locked tokens cannot be withdrawn for lockDuration and are eligible to receive stakingReward rewards
    function lock(
        address _account,
        uint256 _amount,
        uint256 _chainId
    ) external payable nonReentrant onlySelf {
        //lock
        _lock(_account, _amount, false, _chainId);
    }

    function lockOnThisChain(
        address _account,
        uint256 _amount,
        uint256[] calldata _values
    ) external payable nonReentrant onlyQLqdr {
        require(_values.length == chainsLength, "Values length not correct");
        bytes memory payload = abi.encode("lock", _account, _amount);

        for (uint256 i = 0; i < chainsLength; i++) {
            gasService.payNativeGasForContractCall{value: _values[i]}(
                address(this),
                chains[i],
                gateways[i],
                payload,
                msg.sender
            );
            gateway.callContract(chains[i], gateways[i], payload);
        }
    }

    //lock tokens
    function _lock(
        address _account,
        uint256 _amount,
        bool _isRelock,
        uint256 _chainId
    ) internal {
        require(_amount > 0, "Cannot stake 0");
        require(!isShutdown, "shutdown");

        Balances storage bal = balances[_account][_chainId];

        //must try check pointing epoch first
        _checkpointEpoch(_chainId);

        uint112 lockAmount = _amount.to112();

        //add user balances
        bal.locked = bal.locked.add(lockAmount);

        //add to total supplies
        lockedSupply[_chainId] = lockedSupply[_chainId].add(lockAmount);

        //add user lock records or add to current
        uint256 lockEpoch = block.timestamp.div(rewardsDuration).mul(
            rewardsDuration
        );
        //if a fresh lock, add on an extra duration period
        if (!_isRelock) {
            lockEpoch = lockEpoch.add(rewardsDuration);
        }
        uint256 unlockTime = lockEpoch.add(lockDuration);
        uint256 idx = userLocks[_account][_chainId].length;

        //if the latest user lock is smaller than this lock, always just add new entry to the end of the list
        if (
            idx == 0 ||
            userLocks[_account][_chainId][idx - 1].unlockTime < unlockTime
        ) {
            userLocks[_account][_chainId].push(
                LockedBalance({
                    amount: lockAmount,
                    unlockTime: uint32(unlockTime)
                })
            );
        } else {
            //else add to a current lock

            //if latest lock is further in the future, lower index
            //this can only happen if relocking an expired lock after creating a new lock
            if (
                userLocks[_account][_chainId][idx - 1].unlockTime > unlockTime
            ) {
                idx--;
            }

            //if idx points to the epoch when same unlock time, update
            //(this is always true with a normal lock but maybe not with relock)
            if (
                userLocks[_account][_chainId][idx - 1].unlockTime == unlockTime
            ) {
                LockedBalance storage userL = userLocks[_account][_chainId][
                    idx - 1
                ];
                userL.amount = userL.amount.add(lockAmount);
            } else {
                //can only enter here if a relock is made after a lock and there's no lock entry
                //for the current epoch.
                //ex a list of locks such as "[...][older][current*][next]" but without a "current" lock
                //length - 1 is the next epoch
                //length - 2 is a past epoch
                //thus need to insert an entry for current epoch at the 2nd to last entry
                //we will copy and insert the tail entry(next) and then overwrite length-2 entry

                //reset idx
                idx = userLocks[_account][_chainId].length;

                //get current last item
                LockedBalance storage userL = userLocks[_account][_chainId][
                    idx - 1
                ];

                //add a copy to end of list
                userLocks[_account][_chainId].push(
                    LockedBalance({
                        amount: userL.amount,
                        unlockTime: userL.unlockTime
                    })
                );

                //insert current epoch lock entry by overwriting the entry at length-2
                userL.amount = lockAmount;
                userL.unlockTime = uint32(unlockTime);
            }
        }

        //update epoch supply, epoch checkpointed above so safe to add to latest
        uint256 eIndex = epochs[_chainId].length - 1;
        //if relock, epoch should be current and not next, thus need to decrease index to length-2
        if (_isRelock) {
            eIndex--;
        }
        Epoch storage e = epochs[_chainId][eIndex];
        e.supply = e.supply.add(uint224(lockAmount));

        emit Staked(_account, lockEpoch, _amount, lockAmount);
    }

    // Withdraw all currently locked tokens where the unlock time has passed
    function _processExpiredLocks(
        address _account,
        bool _relock,
        address _withdrawTo,
        address,
        uint256 _checkDelay,
        uint256 _chainId
    ) internal {
        LockedBalance[] storage locks = userLocks[_account][_chainId];
        Balances storage userBalance = balances[_account][_chainId];
        uint112 locked;
        uint256 length = locks.length;
        uint256 reward = 0;

        if (
            isShutdown ||
            locks[length - 1].unlockTime <= block.timestamp.sub(_checkDelay)
        ) {
            //if time is beyond last lock, can just bundle everything together
            locked = userBalance.locked;

            //dont delete, just set next index
            userBalance.nextUnlockIndex = length.to32();

            //check for kick reward
            //this wont have the exact reward rate that you would get if looped through
            //but this section is supposed to be for quick and easy low gas processing of all locks
            //we'll assume that if the reward was good enough someone would have processed at an earlier epoch
            if (_checkDelay > 0) {
                uint256 currentEpoch = block
                    .timestamp
                    .sub(_checkDelay)
                    .div(rewardsDuration)
                    .mul(rewardsDuration);
                uint256 epochsover = currentEpoch
                    .sub(uint256(locks[length - 1].unlockTime))
                    .div(rewardsDuration);
                uint256 rRate = MathUtil.min(
                    kickRewardPerEpoch.mul(epochsover + 1),
                    denominator
                );
                reward = uint256(locks[length - 1].amount).mul(rRate).div(
                    denominator
                );
            }
        } else {
            //use a processed index(nextUnlockIndex) to not loop as much
            //deleting does not change array length
            uint32 nextUnlockIndex = userBalance.nextUnlockIndex;
            for (uint i = nextUnlockIndex; i < length; i++) {
                //unlock time must be less or equal to time
                if (locks[i].unlockTime > block.timestamp.sub(_checkDelay))
                    break;

                //add to cumulative amounts
                locked = locked.add(locks[i].amount);

                //check for kick reward
                //each epoch over due increases reward
                if (_checkDelay > 0) {
                    uint256 currentEpoch = block
                        .timestamp
                        .sub(_checkDelay)
                        .div(rewardsDuration)
                        .mul(rewardsDuration);
                    uint256 epochsover = currentEpoch
                        .sub(uint256(locks[i].unlockTime))
                        .div(rewardsDuration);
                    uint256 rRate = MathUtil.min(
                        kickRewardPerEpoch.mul(epochsover + 1),
                        denominator
                    );
                    reward = reward.add(
                        uint256(locks[i].amount).mul(rRate).div(denominator)
                    );
                }
                //set next unlock index
                nextUnlockIndex++;
            }
            //update next unlock index
            userBalance.nextUnlockIndex = nextUnlockIndex;
        }
        require(locked > 0, "no exp locks");

        //update user balances and total supplies
        userBalance.locked = userBalance.locked.sub(locked);
        lockedSupply[_chainId] = lockedSupply[_chainId].sub(locked);

        emit Withdrawn(_account, locked, _relock);

        //relock or return to user
        if (_relock) {
            _lock(_withdrawTo, locked, true, _chainId);
        }
    }

    // withdraw expired locks to a different address
    function withdrawExpiredLocksTo(
        address _withdrawTo,
        uint256 _chainId
    ) external nonReentrant {
        _processExpiredLocks(
            msg.sender,
            false,
            _withdrawTo,
            msg.sender,
            0,
            _chainId
        );
    }

    function withdrawExpiredLocksToOnThisChain(
        address _withdrawTo,
        uint256[] calldata _values
    ) external payable nonReentrant onlyQLqdr {
        require(_values.length == chainsLength, "Values length not correct");
        bytes memory payload = abi.encode(
            "withdrawExpiredLocksTo",
            _withdrawTo
        );

        for (uint256 i = 0; i < chainsLength; i++) {
            gasService.payNativeGasForContractCall{value: _values[i]}(
                address(this),
                chains[i],
                gateways[i],
                payload,
                msg.sender
            );
            gateway.callContract(chains[i], gateways[i], payload);
        }
    }

    // Withdraw/relock all currently locked tokens where the unlock time has passed
    function processExpiredLocks(
        bool _relock,
        uint256 _chainId
    ) external nonReentrant {
        _processExpiredLocks(
            msg.sender,
            _relock,
            msg.sender,
            msg.sender,
            0,
            _chainId
        );
    }

    function processExpiredLocksOnThisChain(
        bool _relock,
        uint256[] calldata _values
    ) external payable nonReentrant onlyQLqdr {
        require(_values.length == chainsLength, "Values length not correct");
        bytes memory payload = abi.encode("processExpiredLocks", _relock);

        for (uint256 i = 0; i < chainsLength; i++) {
            gasService.payNativeGasForContractCall{value: _values[i]}(
                address(this),
                chains[i],
                gateways[i],
                payload,
                msg.sender
            );
            gateway.callContract(chains[i], gateways[i], payload);
        }
    }

    function kickExpiredLocks(
        address _account,
        uint256 _chainId
    ) external nonReentrant {
        //allow kick after grace period of 'kickRewardEpochDelay'
        _processExpiredLocks(
            _account,
            false,
            _account,
            msg.sender,
            rewardsDuration.mul(kickRewardEpochDelay),
            _chainId
        );
    }

    function kickExpiredLocksOnThisChain(
        address _account,
        uint256[] calldata _values
    ) external payable nonReentrant onlyQLqdr {
        require(_values.length == chainsLength, "Values length not correct");
        bytes memory payload = abi.encode("kickExpiredLocks", _account);

        for (uint256 i = 0; i < chainsLength; i++) {
            gasService.payNativeGasForContractCall{value: _values[i]}(
                address(this),
                chains[i],
                gateways[i],
                payload,
                msg.sender
            );
            gateway.callContract(chains[i], gateways[i], payload);
        }
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // Added to support recovering LP Rewards from other systems such as BAL to be distributed to holders
    function recoverERC20(
        address _tokenAddress,
        uint256 _tokenAmount
    ) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(owner(), _tokenAmount);
        emit Recovered(_tokenAddress, _tokenAmount);
    }

    /* ========== EVENTS ========== */
    event Staked(
        address indexed _user,
        uint256 indexed _epoch,
        uint256 _paidAmount,
        uint256 _lockedAmount
    );
    event Withdrawn(address indexed _user, uint256 _amount, bool _relocked);
    event KickReward(
        address indexed _user,
        address indexed _kicked,
        uint256 _reward
    );
    event Recovered(address _token, uint256 _amount);

    receive() external payable {}

    fallback() external {}
}

