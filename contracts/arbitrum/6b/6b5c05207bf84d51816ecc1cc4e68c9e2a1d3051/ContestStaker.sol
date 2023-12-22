// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { IERC1155 } from "./IERC1155.sol";
import { Multicall } from "./Multicall.sol";
import { ERC1155Holder } from "./ERC1155Holder.sol";
import { EnumerableSet } from "./EnumerableSet.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

// Anyone can stake a designated ERC1155 token into this contract, and they can choose which token ID to stake
// provided the ID is whitelisted (see the private stakeableTokenIds set). This contract provides internal methods that
// another contract can use to append to the stakeable token ID set and register contests, which can freeze and
// unfreeze user's stakes. The idea is that the contests can freeze a user's stake if they submit an entry,
// and unfreeze it if they withdraw their entry. The contests can also transfer a user's frozen stake,
// which could be used to take a winner's stake for example. The advantage of this design is that a user's stake
// can be re-used for multiple contests and they only need to interface with this staking contract, instead of
// approving and staking per contest entered.

error UnregisteredContest();
error AddToSetFailed();
error StakedContractNotExists();
error TokenIdNotExists();
error InvalidStakedContract();
error InvalidTokenId();
error InvalidInputAmount();
error InsufficientStake(uint256 usableStake, uint256 requestedStake);
error InsufficientFrozenStake(uint256 frozenStake, uint256 requestedStake);
error InitialSettingStakeableTokenIdFailed();

interface IContestStaker {
    function freezeStake(address stakedContract, uint256 tokenId, address staker, uint256 amount) external;
    function unfreezeStake(address stakedContract, uint256 tokenId, address staker, uint256 amount) external;
    function transferFrozenStake(
        address stakedContract,
        uint256 tokenId,
        address staker,
        address recipient,
        uint256 amount
    )
        external;
    function canUseStake(address stakedContract, uint256 tokenId, address staker) external view returns (bool);
}

contract ContestStaker is IContestStaker, ERC1155Holder, ReentrancyGuard, Multicall {
    using EnumerableSet for EnumerableSet.UintSet;

    // Whitelisted token IDs that can be staked. This set is append-only to eliminate situation where a user has
    // staked a token ID that is no longer whitelisted.
    mapping(address => bool) public stakedContracts;
    mapping(address => EnumerableSet.UintSet) private stakeableTokenIds;

    // contract address => tokenId => staker => stake amount.
    mapping(address => mapping(uint256 => mapping(address => uint256))) public stakes;
    mapping(address => mapping(uint256 => mapping(address => uint256))) public frozenStakes;

    // Contests can put a hold on a user's stake.
    mapping(address => bool) public contests;

    modifier onlyContest() {
        if (!contests[msg.sender]) revert UnregisteredContest();
        _;
    }

    event Staked(address indexed stakedContract, uint256 indexed tokenId, uint256 amount, address indexed staker);
    event Unstaked(address indexed stakedContract, uint256 indexed tokenId, uint256 amount, address indexed staker);
    event AddedTokenId(address indexed stakedContract, uint256 indexed tokenId);
    event RemovedStakedContract(address indexed stakedContract);
    event RemovedTokenId(address indexed stakedContract, uint256 indexed tokenId);
    event FreezeStake(address indexed stakedContract, uint256 indexed tokenId, address indexed staker, uint256 amount);
    event UnfreezeStake(
        address indexed stakedContract, uint256 indexed tokenId, address indexed staker, uint256 amount
    );
    event TransferFrozenStake(
        address indexed stakedContract,
        uint256 indexed tokenId,
        address indexed staker,
        address recipient,
        uint256 amount
    );

    // @dev This will revert if `_stakeableTokenIds` contains duplicate ID's or ones that otherwise fail to add to the
    // stakeableTokenIds set.
    constructor(address _stakedContract, uint256[] memory _stakeableTokenIds) {
        stakedContracts[_stakedContract] = true;
        uint256 len = _stakeableTokenIds.length;
        for (uint256 i; i < len;) {
            if (!stakeableTokenIds[_stakedContract].add(_stakeableTokenIds[i])) {
                revert InitialSettingStakeableTokenIdFailed();
            }
            emit AddedTokenId(_stakedContract, _stakeableTokenIds[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     *
     * Contest functions: Can only be called by whitelisted contest contract.
     *
     */

    // Invariant: stake amount should always be >= frozen stake amount.
    /**
     * @notice Freeze 1 stake of user
     */
    function freezeStake(
        address stakedContract,
        uint256 tokenId,
        address staker,
        uint256 amount
    )
        external
        override
        onlyContest
    {
        if (!stakedContracts[stakedContract]) revert InvalidStakedContract();
        if (!stakeableTokenIds[stakedContract].contains(tokenId)) revert InvalidTokenId();
        if (getUsableStake(stakedContract, tokenId, staker) < amount) {
            revert InsufficientStake(getUsableStake(stakedContract, tokenId, staker), amount);
        }
        frozenStakes[stakedContract][tokenId][staker] += amount;
        emit FreezeStake(stakedContract, tokenId, staker, amount);
    }

    function unfreezeStake(
        address stakedContract,
        uint256 tokenId,
        address staker,
        uint256 amount
    )
        external
        override
        onlyContest
    {
        if (frozenStakes[stakedContract][tokenId][staker] < amount) {
            revert InsufficientFrozenStake(frozenStakes[stakedContract][tokenId][staker], amount);
        }
        frozenStakes[stakedContract][tokenId][staker] -= amount;
        emit UnfreezeStake(stakedContract, tokenId, staker, amount);
    }

    // Only stake frozen by contest can be transferred away to recipient. Decrements both stakes
    // and frozen stakes amount of user.
    function transferFrozenStake(
        address stakedContract,
        uint256 tokenId,
        address staker,
        address recipient,
        uint256 amount
    )
        external
        override
        onlyContest
        nonReentrant
    {
        if (frozenStakes[stakedContract][tokenId][staker] < amount) {
            revert InsufficientFrozenStake(frozenStakes[stakedContract][tokenId][staker], amount);
        }
        stakes[stakedContract][tokenId][staker] -= amount;
        frozenStakes[stakedContract][tokenId][staker] -= amount;
        IERC1155(address(stakedContract)).safeTransferFrom(address(this), recipient, tokenId, amount, "");
        emit TransferFrozenStake(stakedContract, tokenId, staker, recipient, amount);
    }

    /**
     *
     * Public functions.
     *
     */

    /**
     * @notice Increase stake amount. Cannot send any staked amount that was frozen by a contest.
     * @dev Caller must approve this contract to transfer the token ID.
     */
    function stake(address stakedContract, uint256 tokenId, uint256 amount) external nonReentrant {
        if (!stakedContracts[stakedContract]) revert InvalidStakedContract();
        if (!stakeableTokenIds[stakedContract].contains(tokenId)) revert InvalidTokenId();
        if (amount == 0) revert InvalidInputAmount();
        stakes[stakedContract][tokenId][msg.sender] += amount;
        IERC1155(address(stakedContract)).safeTransferFrom(msg.sender, address(this), tokenId, amount, "");
        emit Staked(stakedContract, tokenId, amount, msg.sender);
    }

    /**
     * @notice Send stake back to user. Cannot send any staked amount that was frozen by a contest.
     */
    function unstake(address stakedContract, uint256 tokenId, uint256 amount) external nonReentrant {
        if (getUsableStake(stakedContract, tokenId, msg.sender) < amount) {
            revert InsufficientStake(getUsableStake(stakedContract, tokenId, msg.sender), amount);
        }
        if (amount == 0) revert InvalidInputAmount();
        stakes[stakedContract][tokenId][msg.sender] -= amount;
        IERC1155(address(stakedContract)).safeTransferFrom(address(this), msg.sender, tokenId, amount, "");
        emit Unstaked(stakedContract, tokenId, amount, msg.sender);
    }

    /**
     *
     * View functions
     *
     */

    function getStakeableTokenIds(address stakedContract) public view returns (uint256[] memory) {
        return stakeableTokenIds[stakedContract].values();
    }

    // This could theoretically run out of gas if token ID count is very high.
    // Returns stake amount for user for each token ID returned by `getStakeableTokenIds`. Returns in same order
    // as `getStakeableTokenIds` so caller should be sure to merge on indices.
    function getStakeAmountsForUser(address stakedContract, address user) external view returns (uint256[] memory) {
        uint256[] memory allTokenIds = getStakeableTokenIds(stakedContract);
        uint256 len = allTokenIds.length;
        for (uint256 i; i < len;) {
            allTokenIds[i] = getUsableStake(stakedContract, allTokenIds[i], user);
            unchecked {
                ++i;
            }
        }
        return allTokenIds;
    }

    function getUsableStake(address stakedContract, uint256 tokenId, address staker) public view returns (uint256) {
        return stakes[stakedContract][tokenId][staker] - frozenStakes[stakedContract][tokenId][staker];
    }

    function canUseStake(
        address stakedContract,
        uint256 tokenId,
        address staker
    )
        external
        view
        override
        returns (bool)
    {
        return getUsableStake(stakedContract, tokenId, staker) > 0;
    }

    function isStakedContract(address stakedContract) external view returns (bool) {
        return stakedContracts[stakedContract];
    }
    /**
     *
     * Internal functions
     *
     */

    // Register a contest that can freeze and unfreeze stakes.
    function _registerContest(address contest) internal {
        contests[contest] = true;
    }

    // Add a token ID that can be staked.
    function _addStakeableTokenId(address stakedContract, uint256 tokenId) internal {
        stakedContracts[stakedContract] = true;
        bool success = stakeableTokenIds[stakedContract].add(tokenId);
        if (!success) revert AddToSetFailed();
        emit AddedTokenId(stakedContract, tokenId);
    }

    // Remove a staked contract.
    function _removeStakedContract(address stakedContract) internal {
        if (!stakedContracts[stakedContract]) revert StakedContractNotExists();
        stakedContracts[stakedContract] = false;
        uint256[] memory tokenIds = stakeableTokenIds[stakedContract].values();
        uint256 len = tokenIds.length;
        for (uint256 i; i < len;) {
            stakeableTokenIds[stakedContract].remove(tokenIds[i]);
            unchecked {
                ++i;
            }
        }
        emit RemovedStakedContract(stakedContract);
    }

    // Remove a token ID that can be staked.
    function _removeStakeableTokenId(address stakedContract, uint256 tokenId) internal {
        if (!stakedContracts[stakedContract] || !stakeableTokenIds[stakedContract].contains(tokenId)) {
            revert TokenIdNotExists();
        }
        stakeableTokenIds[stakedContract].remove(tokenId);
        emit RemovedTokenId(stakedContract, tokenId);
    }
}

