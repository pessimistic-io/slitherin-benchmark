// SPDX-License-Identifier: none
pragma solidity ^0.8.18;

import "./ERC20.sol";
import "./ERC20Burnable.sol";
import "./ERC20FlashMint.sol";
import "./AccessControl.sol";

interface IFCO {
    struct LockInfo {
        uint128 start;
        uint128 count;
    }

    struct Lock {
        uint216 amount;
        uint40 unlockTime;
    }

    struct AggregateData {
        string name;
        string symbol;
        uint decimals;
        uint256 balance;
        uint256 locked;
        uint256 unlocked;
        uint256 auction;
        uint256 rewardsEpoch;
        LockInfo locksInfo;
        Lock[] locks;
    }

    struct RewardItem {
        address account;
        uint128 mint;
        uint128 lock;
    }
    enum RewardResult {
        OK,
        SIGNUP,
        ALREADY_REWARDED,
        WRONG_AMOUNT,
        WRONG_MINT_AMOUNT
    }
    function aggregate(address account) external view returns (AggregateData memory data);

    function auctionUse(address account, uint216 amount) external;

    function auctionReturn(address account, uint216 amount, address mintTo) external;

    function votingLocked(address account) external returns (uint256);
}

contract FCO is IFCO, ERC20, ERC20Burnable, ERC20FlashMint, AccessControl {

    // ------------------------------- STORAGE -------------------------------

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant REWARDS_MANAGER_ROLE = keccak256("REWARDS_MANAGER_ROLE");
    bytes32 public constant AUCTION_ROLE = keccak256("AUCTION_ROLE");

    uint128 public constant SIGNUP_REWARD = 3 * 1e18; // 3 token max per signup
    uint128 public constant EPOCH_REWARD = 1 * 1e18; // 1 token max per day
    uint128 public constant MAX_TRANSFER = 1_000_000 * 1e18; // 1 million tokens max per transfer
    uint32 public constant EPOCH_DURATION = 1 days;
    uint32 public constant LOCK_DURATION = EPOCH_DURATION * 30;

    mapping(address => LockInfo) public locksInfos;
    mapping(address => mapping(uint256 => Lock)) public locks;
    mapping(address => uint256) public votingLocked;
    mapping(address => uint256) public auctionLocked;
    mapping(address => uint40) public rewardsEpoch;

    // ------------------------------- CONSTRUCT -------------------------------

    constructor(string memory name, string memory symbol, address admin) ERC20(name, symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ------------------------------- VIEW -------------------------------

    // all required data in single request    
    function aggregate(address account) public view returns (AggregateData memory data) {
        data.name = name();
        data.symbol = symbol();
        data.decimals = decimals();
        data.balance = balanceOf(account);
        (data.locked, data.unlocked) = internalBalance(account);
        data.auction = auctionLocked[account];
        data.rewardsEpoch = rewardsEpoch[account];

        LockInfo memory locksInfo = locksInfos[account];
        data.locksInfo = locksInfo;

        data.locks = new Lock[](locksInfo.count - locksInfo.start);
        uint idx;
        for (uint i = locksInfo.start; i < locksInfo.count;) {
            data.locks[idx] = locks[account][i];
            unchecked {i++;
                idx ++;}
        }
    }

    // calculates current locked tokens of account
    function internalBalance(address account) public view returns (uint256 locked, uint256 unlocked) {
        LockInfo memory locksInfo = locksInfos[account];
        for (uint i = locksInfo.start; i < locksInfo.count;) {
            Lock memory userLock = locks[account][i];
            if (userLock.unlockTime > block.timestamp) {
                locked += userLock.amount;
            } else {
                unlocked += userLock.amount;
            }
            unchecked {i++;}
        }
    }

    // calculates current epoch
    function currentEpoch() public view returns (uint40) {
        return uint40(block.timestamp / EPOCH_DURATION * EPOCH_DURATION);
    }

    // ------------------------------- PUBLIC -------------------------------

    // flash loan consider voting locked 
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes calldata data) public override returns (bool result) {
        votingLocked[address(receiver)] += amount;
        votingLocked[msg.sender] += amount;

        token = address(this);
        result = super.flashLoan(receiver, token, amount, data);

        votingLocked[address(receiver)] = 0;
        votingLocked[msg.sender] = 0;
    }

    // for case if user has too much locks and out of gas on transfer execution 
    function unlock(uint128 count) public {
        uint216 unlocked = _unlock(msg.sender, 0, count);
        require(unlocked != 0, "Nothing to unlock");
        _mint(msg.sender, unlocked);
    }

    // ------------------------------- MINTER -------------------------------

    function mint(address account, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(account, amount);
    }

    function lock(address account, uint216 amount) public onlyRole(MINTER_ROLE) {
        _validTransferAmount(amount, true);
        _lock(account, amount);
    }

    // ------------------------------- REWARDS MANAGER -------------------------------

    // process signup or rewards distribution
    function processRewards(RewardItem[] calldata rewardItems) public onlyRole(REWARDS_MANAGER_ROLE) returns (RewardResult[] memory results) {
        results = new RewardResult[](rewardItems.length);

        for (uint256 i = 0; i < rewardItems.length; i++) {
            address account = rewardItems[i].account;
            uint40 lastEpoch = rewardsEpoch[account];
            uint40 currEpoch = currentEpoch();

            if (lastEpoch == 0) {
                rewardsEpoch[account] = currEpoch;
                _lock(account, SIGNUP_REWARD);

                results[i] = RewardResult.SIGNUP;
                emit Signup(account, SIGNUP_REWARD);
                continue;
            }

            if (lastEpoch == currEpoch) {
                results[i] = RewardResult.ALREADY_REWARDED;
                continue;
            }

            uint128 mintAmount = rewardItems[i].mint;
            uint128 lockAmount = rewardItems[i].lock;
            uint128 amount = mintAmount + lockAmount;

            uint40 timePast = currEpoch - lastEpoch;
            uint40 numberEpochsPast = timePast / EPOCH_DURATION;

            if (amount > numberEpochsPast * EPOCH_REWARD
                || !_validTransferAmount(amount, false)
                || !_nonZeroAmount(amount, false)
            ) {
                results[i] = RewardResult.WRONG_AMOUNT;
                continue;
            }

            if (mintAmount != 0) {
                uint216 allowedMintAmount = timePast > LOCK_DURATION ? (timePast - LOCK_DURATION) / EPOCH_DURATION * EPOCH_REWARD : 0;

                if (mintAmount > allowedMintAmount) {
                    results[i] = RewardResult.WRONG_MINT_AMOUNT;
                    continue;
                }

                _mint(account, mintAmount);
            }

            if (lockAmount != 0) {
                _lock(account, lockAmount);
            }

            rewardsEpoch[account] = currEpoch;

            emit Reward(account, mintAmount, lockAmount, currEpoch);
        }
    }

    // ------------------------------- AUCTION -------------------------------

    function auctionUse(address account, uint216 amount) public onlyRole(AUCTION_ROLE) {
        _nonZeroAmount(amount, true);
        _validTransferAmount(amount, true);

        require(tx.origin == account, "Not allowed");

        (uint256 unlocked, uint256 locked) = internalBalance(account); // unlock all possible locks first if they expired
        uint256 unlockAmount = unlocked + locked;

        require(amount <= balanceOf(account) + unlockAmount, "Low collated balance"); // check if is enough entire balance

        if (amount >= unlockAmount) {// if not enough unlocked
            locksInfos[account] = LockInfo(0, 0); // unlock all
            if (amount > unlockAmount) {
                _burn(account, amount - unlockAmount); // burn left over 
            }
        } else {
            _unlock(account, amount, 0);
        }

        auctionLocked[account] += amount;
    }

    function auctionReturn(address account, uint216 amount, address to) public onlyRole(AUCTION_ROLE) {
        require(auctionLocked[account] >= amount, "Low auction balance");
        unchecked {
            auctionLocked[account] -= amount;
        }

        if (to != address(0)) {
            _mint(to, amount);
        } else {
            _nonZeroAmount(amount, true);
            _validTransferAmount(amount, true);
            _lock(account, amount);
        }
    }

    // ------------------------------- INTERNAL -------------------------------

    function _beforeTokenTransfer(address from, address, uint256 amount) internal override {
        _nonZeroAmount(amount, true);

        if (votingLocked[msg.sender] == 0) {
            _validTransferAmount(amount, true);
        } else {
            return; // flash loan 
        }

        if (from == address(0)) return;

        uint216 unlocked = _unlock(from, 0, 0); // unlock all possible locks first if they expired in every transfer                     
        if (unlocked != 0) _mint(from, unlocked);
    }

    function _lock(address account, uint216 amount) private {
        uint40 unlockTime = currentEpoch() + LOCK_DURATION;

        LockInfo storage locksInfo = locksInfos[account];

        if (locksInfo.count == 0 || unlockTime > locks[account][locksInfo.count - 1].unlockTime) {
            locks[account][locksInfo.count] = Lock(amount, unlockTime);
            locksInfo.count ++;
        } else {
            locks[account][locksInfo.count - 1].amount += amount;
        }

        emit LockTokens(account, amount, unlockTime);
    }

    function _unlock(address account, uint216 unlockAmount, uint128 count) private returns (uint216 unlocked) {
        LockInfo memory locksInfo = locksInfos[account];

        if (locksInfo.count == 0) return unlocked; // if no locks present skip next

        if (count == 0) {// if common unlock
            count = locksInfo.count;
        } else {// if count provided check it
            require(count >= locksInfo.start && count <= locksInfo.count, "Bad range");
        }

        for (uint256 i = locksInfo.start; i < count;) {
            Lock storage userLock = locks[account][i];

            if (unlockAmount == 0) {// if unlock amount not specified
                if (userLock.unlockTime <= block.timestamp) {// unlock all expired locks
                    unlocked += userLock.amount; // unlock entire
                    locksInfo.start ++; // shift start index forward
                } else {
                    break;
                }
            } else {// if unlock amount requested (auction)
                uint216 remaining = unlockAmount - unlocked; // determine remaining amount
                if (remaining > userLock.amount) {// if remaining amount higher then current lock amount
                    unlocked += userLock.amount; // unlock entire 
                    locksInfo.start ++; // shift start index forward
                } else {
                    unchecked {
                        userLock.amount -= remaining; // unlock only remaining
                    }
                    break;
                }
            }
            unchecked {i++;}
        }

        if (unlocked != 0) {
            if (locksInfo.start == locksInfo.count) {// reset locks if reach end
                locksInfos[account] = LockInfo(0, 0);
            } else {
                locksInfos[account].start = locksInfo.start;
            }

            emit UnlockTokens(account, unlocked);
        }
    }

    function _nonZeroAmount(uint256 amount, bool revertOnFalse) internal pure returns (bool success) {
        success = amount != 0;
        if (revertOnFalse) {
            require(success, "Zero amount");
        }
    }

    function _validTransferAmount(uint256 amount, bool revertOnFalse) internal pure returns (bool success) {
        success = amount <= MAX_TRANSFER;
        if (revertOnFalse) {
            require(success, "Max transfer");
        }
    }

    // ------------------------------- EVENTS -------------------------------

    event Signup(address indexed owner, uint256 amount);
    event Reward(address indexed owner, uint128 mint, uint128 lock, uint40 epoch);
    event LockTokens(address indexed owner, uint216 amount, uint40 unlockTime);
    event UnlockTokens(address indexed owner, uint256 amount);
}
