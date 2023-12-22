// SPDX-License-Identifier: BUSL-1.1

/***
 *      ______             _______   __
 *     /      \           |       \ |  \
 *    |  $$$$$$\ __    __ | $$$$$$$\| $$  ______    _______  ______ ____    ______
 *    | $$$\| $$|  \  /  \| $$__/ $$| $$ |      \  /       \|      \    \  |      \
 *    | $$$$\ $$ \$$\/  $$| $$    $$| $$  \$$$$$$\|  $$$$$$$| $$$$$$\$$$$\  \$$$$$$\
 *    | $$\$$\$$  >$$  $$ | $$$$$$$ | $$ /      $$ \$$    \ | $$ | $$ | $$ /      $$
 *    | $$_\$$$$ /  $$$$\ | $$      | $$|  $$$$$$$ _\$$$$$$\| $$ | $$ | $$|  $$$$$$$
 *     \$$  \$$$|  $$ \$$\| $$      | $$ \$$    $$|       $$| $$ | $$ | $$ \$$    $$
 *      \$$$$$$  \$$   \$$ \$$       \$$  \$$$$$$$ \$$$$$$$  \$$  \$$  \$$  \$$$$$$$
 *
 *
 *
 */

pragma solidity ^0.8.13;

import {     OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import {     ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import {Math} from "./Math.sol";
import {SafeCast} from "./SafeCast.sol";
import {     IERC20,     SafeERC20 } from "./SafeERC20.sol";
import {     EnumerableMap } from "./EnumerableMap.sol";
import {     EnumerableSet } from "./EnumerableSet.sol";
import {IQuadratBooster} from "./IQuadratBooster.sol";
import {IQuadratBoosterFactory} from "./IQuadratBoosterFactory.sol";
import {     BasePayload,     DepositInfo,     InitializePayload } from "./SQuadratBooster.sol";
import {PriorityQueue} from "./PriorityQueue.sol";

/// @title QuadratBoosterStorage base contract containing all QuadratBooster storage variables.
// solhint-disable-next-line max-states-count
abstract contract QuadratBoosterStorage is
    IQuadratBooster,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using EnumerableMap for EnumerableMap.UintToUintMap;
    using EnumerableSet for EnumerableSet.AddressSet;
    using PriorityQueue for PriorityQueue.Heap;
    using SafeCast for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant MULTIPLIER = 1e16;
    uint256 public constant ONE_HUNDRED = 100;

    // The DEPOSIT TOKEN
    IERC20 public override depositToken;
    // Block number when bonus period ends.
    uint64 public override toBlock;
    // The REWARD TOKEN
    IERC20 public override rewardToken;
    // Block number when bonus period starts.
    uint64 public override fromBlock;
    // Reward tokens per block.
    uint256 public override rewardPerBlock;
    // Reward tokens already claimed.
    uint256 public override rewardClaimed;
    // Current DEPOSIT TOKEN balance.
    uint256 public override totalDeposit;
    // Current DEPOSIT TOKEN virtual balance.
    uint256 public override virtualTotalDeposit;
    // Current cumulative rewardPerShare * MULTIPLIER.
    uint256 public override cumulativeRewardPerShare;
    // Current cumulative blockNumber.
    uint64 public override cumulativeRewardBlockNumber;
    // Reward tokens locked by cumulativeRewardBlockNumber.
    uint256 internal _cumulativeReward;
    // Bonus block number
    uint64 internal _bonusBlockNumber;
    // Bonus multiplier in percent.
    // 20 means 20% more rewards who deposits before bonusBlockNumber.
    uint16 internal _blockBonus;
    // Minimal block numbers for staking.
    uint64 public override minimalWithdrawBlocks;
    // Timed deposit bonus.
    EnumerableMap.UintToUintMap internal _timedBonus;
    // Info of each user that stakes token.
    mapping(address => DepositInfo) public override deposits;
    // Historical Cumulative Reward Per Shares.
    mapping(uint64 => uint256) public override cumulativeRewardPerShares;
    // Enumerable collection of depositors.
    EnumerableSet.AddressSet internal _depositors;
    // Timed virtual amounts
    PriorityQueue.Heap internal _timedAmounts;
    // Minimal deposit value for staking.
    uint256 public override minimalDepositAmount;
    // Booster factory address
    address public override factory;
    // Stop signal constants
    bytes32 internal constant _STARTED = keccak256("started");
    bytes32 internal constant _STOPPED = keccak256("stopped");
    // stopped signal
    bytes32 internal _stopped;
    // storage gap for future needs
    uint256[52] internal _gap;

    modifier nonStopped() {
        require(!isStopped(), "!stopped");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes Booster.
     * @param payload_ Payload in bytes
     */
    function initialize(bytes calldata payload_) external override initializer {
        InitializePayload memory payload = abi.decode(
            payload_,
            (InitializePayload)
        );
        require(
            payload.fromBlock > block.number &&
                payload.toBlock > payload.fromBlock,
            "BN"
        );
        require(
            payload.depositToken != address(0) &&
                payload.rewardToken != address(0),
            "ZA"
        );
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        depositToken = IERC20(payload.depositToken);
        rewardToken = IERC20(payload.rewardToken);
        fromBlock = payload.fromBlock;
        toBlock = payload.toBlock;
        _bonusBlockNumber = payload.bonusBlockNumber;
        _blockBonus = payload.blockBonus;
        minimalWithdrawBlocks = payload.minimalWithdrawBlocks;
        minimalDepositAmount = payload.minimalDepositAmount;
        if (payload.timedBlocks.length > 0) {
            setTimedBonus(payload.timedBlocks, payload.timedBonuses);
        }
        _transferOwnership(payload.owner);
        factory = _msgSender();
        _stopped = _STARTED;
    }

    /**
     * @dev Transfers user deposit.
     * @param to address
     */
    function transferDeposit(address to) external override nonReentrant {
        address _sender = _msgSender();
        DepositInfo storage deposit = deposits[_sender];
        require(deposit.amount > 0, "UA");
        require(
            _sender != to && to != address(0) && deposits[to].amount == 0,
            "TA"
        );
        deposits[to] = deposit;
        _depositors.add(to);
        _depositors.remove(_sender);
        delete deposits[_sender];
        IQuadratBoosterFactory(factory).transferUserBooster(_sender, to);
        emit DepositTrasfered(_sender, to, deposit.amount);
    }

    /**
     * @dev Transfer foreign tokens or balance by owner.
     * @param token Token address
     * @param to Transfer address
     */
    function transferExtra(address token, address to)
        external
        override
        onlyOwner
    {
        require(
            token != address(0) && to != address(0) && to != address(this),
            "ZA"
        );
        require(
            token != address(depositToken) && (token != address(rewardToken)),
            "DTA"
        );
        uint256 amount = IERC20(token).balanceOf(address(this));
        require(amount > 0, "ZTB");
        IERC20(token).safeTransfer(to, amount);
        emit ExtraTransfered(_msgSender(), token, to, amount);
    }

    /**
     * @dev Stops rewards and transfer unlocked rewards.
     * @param to Transfer address
     */

    function stop(address to) external override onlyOwner nonStopped {
        require(to != address(0) && to != address(this), "ZA");
        _stopped = _STOPPED;
        updateCumulativeReward();
        uint256 amount = _rewardUnlocked();
        address token = address(rewardToken);
        rewardPerBlock = 0;
        if (amount > 0) {
            IERC20(token).safeTransfer(to, amount);
        }
        emit Stopped(_msgSender(), token, to, amount);
    }

    /**
     * @dev Updates fromBlock number.
     * @param blockNumber A new fromBlock number
     */
    function setFromBlock(uint64 blockNumber)
        external
        override
        onlyOwner
        nonStopped
    {
        address sender = _msgSender();
        require(
            fromBlock != blockNumber &&
                fromBlock > block.number &&
                blockNumber > block.number &&
                blockNumber < toBlock,
            "BN"
        );
        fromBlock = blockNumber;
        _updateReward();
        emit FromBlockUpdated(sender, blockNumber);
    }

    /**
     * @dev Updates toBlock number.
     * @param blockNumber_ A new toBlock number
     */
    function setToBlock(uint64 blockNumber_)
        external
        override
        onlyOwner
        nonStopped
    {
        address sender = _msgSender();
        uint64 blockNumber = block.number.toUint64();
        require(
            toBlock != blockNumber_ &&
                toBlock > blockNumber &&
                blockNumber_ > blockNumber &&
                blockNumber_ > fromBlock,
            "BN"
        );
        updateCumulativeReward();
        toBlock = blockNumber_;
        _updateReward();
        emit ToBlockUpdated(sender, blockNumber_);
    }

    /**
     * @dev Updates fromBlock & toBlock numbers.
     * @param _fromBlockNumber A new fromBlock number
     * @param _toBlockNumber A new toBlock number
     */
    function setFromToBlock(uint64 _fromBlockNumber, uint64 _toBlockNumber)
        external
        override
        onlyOwner
        nonStopped
    {
        address sender = _msgSender();
        require(
            (fromBlock != _fromBlockNumber || toBlock != _toBlockNumber) &&
                fromBlock > block.number &&
                _fromBlockNumber > block.number &&
                _fromBlockNumber < _toBlockNumber,
            "BN"
        );
        fromBlock = _fromBlockNumber;
        toBlock = _toBlockNumber;
        _updateReward();
        emit FromToBlockUpdated(sender, _fromBlockNumber, _toBlockNumber);
    }

    /**
     * @dev Updates block bonus.
     * @param blockNumber_ A new bonus number
     * @param bonus_ Bonus percent
     * @notice Set blockNumber and value to zero to cancel bonus rewards
     */
    function setBlockBonus(uint64 blockNumber_, uint16 bonus_)
        external
        override
        onlyOwner
        nonStopped
    {
        address sender = _msgSender();
        require(
            blockNumber_ != _bonusBlockNumber || bonus_ != _blockBonus,
            "SV"
        );
        require(
            (blockNumber_ < toBlock &&
                blockNumber_ > block.number &&
                bonus_ > 0) || (blockNumber_ == 0 && bonus_ == 0),
            "BBN"
        );
        _bonusBlockNumber = blockNumber_;
        _blockBonus = bonus_;
        emit BlockBonusUpdated(sender, blockNumber_, bonus_);
    }

    /**
     * @dev Sets minimal withdraw blocks.
     * @param blocks The number of blocks
     */
    function setMinimalWithdrawBlocks(uint64 blocks)
        external
        override
        onlyOwner
        nonStopped
    {
        require(minimalWithdrawBlocks != blocks, "SV");
        minimalWithdrawBlocks = blocks;
        emit MinimalWithdrawBlocksUpdated(_msgSender(), blocks);
    }

    /**
     * @dev Sets minimal deposit amount.
     * @param amount The amount
     */
    function setMinimalDepositAmount(uint256 amount)
        external
        override
        onlyOwner
        nonStopped
    {
        require(minimalDepositAmount != amount, "SV");
        minimalDepositAmount = amount;
        emit MinimalDepositAmountUpdated(_msgSender(), amount);
    }

    /**
     * @dev Updates reward per a block after funds transfer.
     */
    function updateReward() external override {
        uint256 _rewardPerBlock = rewardPerBlock;
        _updateReward();
        require(_rewardPerBlock != rewardPerBlock, "SV");
        emit RewardUpdated(_msgSender(), _rewardPerBlock, rewardPerBlock);
    }

    /**
     * @dev Updates cumulative reward by a block specified.
     * @param byBlock By block nubmer
     * @return _cumulativeRewardPerShare A new cumulativeRewardPerShare
     */
    function updateCumulativeRewardByBlock(uint64 byBlock)
        external
        override
        returns (uint256 _cumulativeRewardPerShare)
    {
        require(byBlock <= block.number, "BN");
        _cumulativeRewardPerShare = _updateCumulativeRewardByBlock(byBlock);
    }

    /**
     * @dev Returns cumulative reward per share amount nad block number for its calculation
     * @return (rewardPerBlock, rewardClaimed, rewardLocked, rewardUnlocked)
     */
    function totalReward()
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return (
            rewardPerBlock,
            rewardClaimed,
            _rewardLocked(),
            _rewardUnlocked()
        );
    }

    /**
     * @dev Returns cumulative reward per share amount and block number for its calculation
     * @return (cumulativeReward, cumulativeRewardPerShare, cumulativeRewardBlockNumber)
     */
    function cumulativeReward()
        external
        view
        override
        returns (
            uint256,
            uint64,
            uint256
        )
    {
        return (
            cumulativeRewardPerShare,
            cumulativeRewardBlockNumber,
            _cumulativeReward
        );
    }

    /**
     * @dev Returns block bonus information
     * @return (bonusBlockNumber, blockBonus)
     */
    function blockBonus() external view override returns (uint64, uint256) {
        return (_bonusBlockNumber, _blockBonus);
    }

    /**
     * @dev Returns Pending & Expired time lock deposit blocks.
     */
    function timeLockDepositBlocks()
        external
        view
        override
        returns (uint256, uint256)
    {
        return (_timedAmounts.size, _timedAmounts.numBy(block.number));
    }

    /**
     * @dev Gets contract attributes.
     * @return payload A contract attribute structure
     */
    function viewAttributes()
        external
        view
        override
        returns (InitializePayload memory payload, address booster)
    {
        payload.depositToken = address(depositToken);
        payload.fromBlock = fromBlock;
        payload.rewardToken = address(rewardToken);
        payload.toBlock = toBlock;
        payload.bonusBlockNumber = _bonusBlockNumber;
        payload.blockBonus = _blockBonus;
        payload.minimalWithdrawBlocks = minimalWithdrawBlocks;
        payload.minimalDepositAmount = minimalDepositAmount;
        payload.timedBlocks = new uint32[](_timedBonus.length());
        payload.timedBonuses = new uint16[](_timedBonus.length());
        for (uint256 i = 0; i < _timedBonus.length(); ) {
            (uint256 _block, uint256 _bonus) = _timedBonus.at(i);
            payload.timedBlocks[i] = _block.toUint32();
            payload.timedBonuses[i] = _bonus.toUint16();
            unchecked {
                i++;
            }
        }
        payload.owner = owner();
        booster = address(this);
    }

    /**
     * @dev Transforms payload struct to bytes array to pass it to factory.
     * @param payload InitializePayload data
     * @return bytes array
     */
    function transformPayloadToBytes(InitializePayload calldata payload)
        external
        pure
        override
        returns (bytes memory)
    {
        return abi.encode(payload);
    }

    /**
     * @dev Transforms bytes array to base payload struct.
     * @param data bytes array
     * @return payload BasePayload data
     */
    function transformBytesToBasePayload(bytes calldata data)
        external
        pure
        override
        returns (BasePayload memory payload)
    {
        InitializePayload memory _payload = abi.decode(
            data,
            (InitializePayload)
        );
        payload.depositToken = _payload.depositToken;
        payload.fromBlock = _payload.fromBlock;
        payload.rewardToken = _payload.rewardToken;
        payload.toBlock = _payload.toBlock;
        payload.owner = _payload.owner;
    }

    /**
     * @dev Sets timed deposit bonuses.
     * @param blocks The number of blocks for time lock
     * @param bonuses The bonus percent
     * @notice Set to zero to clear prev timed bonus and add new one
     */
    function setTimedBonus(uint32[] memory blocks, uint16[] memory bonuses)
        public
        override
        onlyOwner
    {
        require(blocks.length > 0 && blocks.length == bonuses.length, "TBL");
        for (uint256 i = 0; i < blocks.length; ) {
            require(blocks[i] > 0, "TB");
            if (bonuses[i] == 0) {
                _timedBonus.remove(blocks[i]);
            } else {
                _timedBonus.set(blocks[i], bonuses[i]);
            }
            unchecked {
                i++;
            }
        }
        emit TimedBonusUpdated(_msgSender(), blocks, bonuses);
    }

    /**
     * @dev Updates cumulative reward by current block.
     * @return _cumulativeRewardPerShare A new cumulativeRewardPerShare
     */
    function updateCumulativeReward()
        public
        override
        returns (uint256 _cumulativeRewardPerShare)
    {
        _cumulativeRewardPerShare = _updateCumulativeRewardByBlock(
            block.number.toUint64()
        );
    }

    /**
     * @dev Timed deposit bonus
     */
    function timedBonus(uint32 blocks) public view override returns (uint16) {
        (, uint256 _bonus) = _timedBonus.tryGet(blocks);
        return _bonus.toUint16();
    }

    /**
     * @dev Returns true if booster stopped. Otherwise false.
     */
    function isStopped() public view override returns (bool) {
        return _stopped == _STOPPED;
    }

    /**
     * @dev Calculates cumulative reward per share without time lock deposits.
     * @return _cumulativeRewardPerShare Updated cumulative reward per share
     */
    function calculateCumulativeReward()
        public
        view
        override
        returns (uint256 _cumulativeRewardPerShare)
    {
        uint64 _blockNumber = Math.min(block.number, toBlock).toUint64();
        uint64 _fromBlock = Math
            .max(cumulativeRewardBlockNumber, fromBlock)
            .toUint64();
        if (_blockNumber > _fromBlock) {
            _cumulativeRewardPerShare = __calculateCumulativeRewardPerShare(
                cumulativeRewardPerShare,
                rewardPerBlock,
                virtualTotalDeposit,
                _fromBlock,
                _blockNumber
            );
        } else {
            _cumulativeRewardPerShare = cumulativeRewardPerShare;
        }
    }

    /**
     * @dev Returns depositor number.
     * @return Depositor amount
     */
    function depositorNum() public view override returns (uint256) {
        return _depositors.length();
    }

    /**
     * @dev Returns depositor addresses.
     * @return Depositors collection
     */
    function depositors() public view override returns (address[] memory) {
        return _depositors.values();
    }

    function _updateReward() internal {
        uint64 _blockNumber = block.number.toUint64();
        require(_blockNumber < toBlock, "BN");
        updateCumulativeReward();
        rewardPerBlock =
            _rewardUnlocked() /
            (toBlock - Math.max(fromBlock, cumulativeRewardBlockNumber));
    }

    function _updateCumulativeRewardByBlock(uint64 byBlock)
        internal
        returns (uint256 _cumulativeRewardPerShare)
    {
        uint64 _blockNumber = Math.min(byBlock, toBlock).toUint64();
        uint64 _fromBlock = Math
            .max(cumulativeRewardBlockNumber, fromBlock)
            .toUint64();
        if (_blockNumber > _fromBlock) {
            uint256 _virtualTotalDeposit;
            (
                _cumulativeRewardPerShare,
                _virtualTotalDeposit
            ) = _updateCumulativeRewardPerShares(
                cumulativeRewardPerShare,
                rewardPerBlock,
                virtualTotalDeposit,
                _fromBlock,
                _blockNumber
            );
            cumulativeRewardBlockNumber = _blockNumber;
            cumulativeRewardPerShare = _cumulativeRewardPerShare;
            virtualTotalDeposit = _virtualTotalDeposit;
            _cumulativeReward +=
                (cumulativeRewardBlockNumber - _fromBlock) *
                rewardPerBlock;
        } else {
            _cumulativeRewardPerShare = cumulativeRewardPerShare;
        }
    }

    function _transferOwnership(address newOwner) internal override {
        require(newOwner != owner(), "SV");
        if (!_isInitializing()) {
            IQuadratBoosterFactory(factory).transferBoosterOwnership(newOwner);
        }
        super._transferOwnership(newOwner);
    }

    function _rewardLocked() internal view returns (uint256 locked) {
        uint64 _blockNumber = block.number.toUint64();
        if (_blockNumber > fromBlock && depositorNum() > 0) {
            locked = (cumulativeRewardBlockNumber == 0)
                ? ((rewardToken.balanceOf(address(this)) -
                    (rewardToken == depositToken ? totalDeposit : 0)) *
                    (Math.min(toBlock, _blockNumber) - fromBlock)) /
                    (toBlock - fromBlock)
                : _cumulativeReward +
                    (Math.min(toBlock, _blockNumber) -
                        cumulativeRewardBlockNumber) *
                    rewardPerBlock -
                    rewardClaimed;
        }
    }

    function _rewardUnlocked() internal view returns (uint256 _balance) {
        _balance = rewardToken.balanceOf(address(this)) - _rewardLocked();
        if (rewardToken == depositToken) {
            _balance -= totalDeposit;
        }
    }

    // solhint-disable-next-line function-max-lines
    function _updateCumulativeRewardPerShares(
        uint256 _cumulativeRewardPerShare,
        uint256 _rewardPerBlock,
        uint256 _virtualTotalDeposit,
        uint64 _fromBlock,
        uint64 _toBlock
    )
        private
        returns (
            uint256 __cumulativeRewardPerShare,
            uint256 __virtualTotalDeposit
        )
    {
        __cumulativeRewardPerShare = _cumulativeRewardPerShare;
        __virtualTotalDeposit = _virtualTotalDeposit;
        while (_timedAmounts.size > 0) {
            uint64 __toBlock = _timedAmounts.headKey().toUint64();
            if (__toBlock > _toBlock) {
                break;
            }
            __cumulativeRewardPerShare = __calculateCumulativeRewardPerShare(
                __cumulativeRewardPerShare,
                _rewardPerBlock,
                __virtualTotalDeposit,
                _fromBlock,
                __toBlock
            );
            __virtualTotalDeposit -= _timedAmounts.dequeue();
            _fromBlock = __toBlock;
            cumulativeRewardPerShares[__toBlock] = __cumulativeRewardPerShare;
        }
        if (_toBlock > _fromBlock) {
            __cumulativeRewardPerShare = __calculateCumulativeRewardPerShare(
                __cumulativeRewardPerShare,
                _rewardPerBlock,
                __virtualTotalDeposit,
                _fromBlock,
                _toBlock
            );
            cumulativeRewardPerShares[_toBlock] = __cumulativeRewardPerShare;
        }
    }

    function __calculateCumulativeRewardPerShare(
        uint256 _cumulativeRewardPerShare,
        uint256 _rewardPerBlock,
        uint256 _virtualTotalDeposit,
        uint64 _fromBlock,
        uint64 _toBlock
    ) private pure returns (uint256 __cumulativeRewardPerShare) {
        __cumulativeRewardPerShare = _cumulativeRewardPerShare;
        if (_toBlock > _fromBlock && _virtualTotalDeposit > 0) {
            __cumulativeRewardPerShare +=
                ((_rewardPerBlock * (_toBlock - _fromBlock)) * MULTIPLIER) /
                _virtualTotalDeposit;
        }
    }
}

