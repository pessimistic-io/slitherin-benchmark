//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC721.sol";
import "./ERC721Holder.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";

contract AngelNFTStaking is Ownable, ReentrancyGuard, ERC721Holder {
    using SafeERC20 for IERC20;

    event NFTStaked(uint256[] tokenIds, address indexed staker);
    event NFTUnstaked(uint256[] tokenIds, address indexed staker);
    event RewardClaimed(address indexed staker);
    event RewardAdded(address token, uint256 amount, uint256 totalStaked);

    address[] public stakersArray;
    mapping(uint256 => address) public stakers;
    mapping(address => uint256[]) public stakedNFTs;

    uint256 public constant MAX_STAKING_AMOUNT = 10;

    IERC721 public angelNFT;
    uint256 public totalStaked;

    address public rewardDistributor;
    address[] public rewardTokens;

    uint256 public constant DEFAULT_DURATION = 40 days;
    mapping(address => uint256) public duration;
    mapping(address => uint256) public rewardRate;
    mapping(address => uint256) public periodFinish;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => uint256) public accRewardPerNFT;
    mapping(address => mapping(uint256 => uint256)) public abortedRewardPerNFT;

    uint256[] private blackList;

    modifier onlyRewardDistributor() {
        require(msg.sender == rewardDistributor, "Staking: NON_DISTRIBUTOR");
        _;
    }

    constructor(IERC721 _angelNFT) {
        angelNFT = _angelNFT;
    }

    function setAngelNFT(IERC721 _angelNFT) external onlyOwner {
        angelNFT = _angelNFT;
    }

    /**
     * @dev set reward distributor by owner
     * reward distributor is the moderator who calls {notifyRewardAmount} function
     * whenever periodic reward tokens transferred to this contract
     * @param distributor new distributor address
     */
    function setRewardDistributor(address distributor) external onlyOwner {
        require(distributor != address(0), "Staking: INVALID_DISTRIBUTOR");
        rewardDistributor = distributor;
    }

    function setBlackList(uint256[] calldata _tokenIds) external onlyOwner {
        blackList = _tokenIds;
    }

    function isAvailable2Stake(uint256 _tokenId) public view returns (bool) {
        if (blackList.length == 0) return true;
        for (uint256 i; i < blackList.length; ++i) {
            if (_tokenId == blackList[i]) return false;
        }
        return true;
    }

    function getStakedNFTS(
        address staker
    ) public view returns (uint256[] memory) {
        return stakedNFTs[staker];
    }

    function getRewardTokens() public view returns (address[] memory) {
        return rewardTokens;
    }

    function usrStaked(address account) external view returns (bool) {
        return stakedNFTs[account].length > 0 ? true : false;
    }

    function lastTimeRewardApplicable(
        address token
    ) public view returns (uint256) {
        return
            block.timestamp < periodFinish[token]
                ? block.timestamp
                : periodFinish[token];
    }

    function accumulatedRewardPerNFT(
        address token
    ) public view returns (uint256) {
        if (totalStaked == 0) {
            return accRewardPerNFT[token];
        } else {
            return
                accRewardPerNFT[token] +
                ((lastTimeRewardApplicable(token) - lastUpdateTime[token]) *
                    rewardRate[token] *
                    1e18) /
                totalStaked;
        }
    }

    /**
     * @dev view total pending reward for staked tokens
     * @param token reward token address
     * @param tokenIds staked nft tokens' ids
     */
    function earned(
        address token,
        uint256[] memory tokenIds
    ) public view returns (uint256 reward) {
        for (uint256 i; i < tokenIds.length; i++) {
            reward +=
                (accumulatedRewardPerNFT(token) -
                    abortedRewardPerNFT[token][tokenIds[i]]) /
                1e18;
        }
    }

    /**
     * @dev stake multiple nft tokens at once
     * @param tokenIds id array of nft tokens being staked
     * @notice emit {NFTStaked} event
     */
    function stake(uint256[] calldata tokenIds) external nonReentrant {
        _updateRewardConditions();

        require(tokenIds.length > 0, "Staking: empty tokens");
        require(
            tokenIds.length <= MAX_STAKING_AMOUNT,
            "Staking: can't exceed maximum staking amount"
        );

        uint256 len = tokenIds.length;
        totalStaked += len;
        for (uint256 i; i < len; i++) {
            require(
                angelNFT.ownerOf(tokenIds[i]) == msg.sender,
                "Staking: can't stake tokens you don't own!"
            );
            require(
                isAvailable2Stake(tokenIds[i]),
                "Staking: can't stake token in blacklist"
            );
            stakers[tokenIds[i]] = msg.sender;
            stakedNFTs[msg.sender].push(tokenIds[i]);
            angelNFT.safeTransferFrom(msg.sender, address(this), tokenIds[i]);
        }

        bool exist;
        for (uint256 i; i < stakersArray.length; i++) {
            exist = exist || (stakersArray[i] == msg.sender);
        }
        if (!exist) stakersArray.push(msg.sender);

        _setAbortedReward(tokenIds);

        emit NFTStaked(tokenIds, msg.sender);
    }

    /**
     * @dev claim rewards after taking out staked nft tokens
     * @param tokenIds id array of nft tokens being unstaked
     * @notice emit {NFTUnstaked} event
     */
    function unstake(uint256[] calldata tokenIds) external nonReentrant {
        _updateRewardConditions();

        require(tokenIds.length > 0, "Staking: invalid tokens");
        require(
            tokenIds.length <= MAX_STAKING_AMOUNT,
            "Staking: can't exceed maximum staking amount"
        );
        
        /// safe transfer staked nft tokens back to user
        /// revert in case of trying to take out tokens user didn't stake
        uint256 len = tokenIds.length;
        totalStaked -= len;
        for (uint256 i; i < len; i++) {
            require(stakers[tokenIds[i]] == msg.sender, "Staking: not staker");
            delete stakers[tokenIds[i]];
            for (uint256 j; j < stakedNFTs[msg.sender].length; j++) {
                if (stakedNFTs[msg.sender][j] == tokenIds[i]) {
                    stakedNFTs[msg.sender][j] = stakedNFTs[msg.sender][
                        stakedNFTs[msg.sender].length - 1
                    ];
                    stakedNFTs[msg.sender].pop();
                    break;
                }
            }
            angelNFT.safeTransferFrom(address(this), msg.sender, tokenIds[i]);
        }

        if (stakedNFTs[msg.sender].length == 0) {
            for (uint256 i; i < stakersArray.length; ++i) {
                if (stakersArray[i] == msg.sender) {
                    stakersArray[i] = stakersArray[stakersArray.length - 1];
                    stakersArray.pop();
                }
            }
        }

        /// claim rewards for all supported reward tokens.
        uint256 reward;
        for (uint256 i; i < rewardTokens.length; i++) {
            reward = earned(rewardTokens[i], tokenIds);
            if (reward > 0) {
                IERC20(rewardTokens[i]).safeTransfer(msg.sender, reward);
            }
        }

        _setAbortedReward(tokenIds);

        emit NFTUnstaked(tokenIds, msg.sender);
    }

    function unstakeAll() external nonReentrant {
        _updateRewardConditions();

        uint256[] memory tokenIds = stakedNFTs[msg.sender];
        require(tokenIds.length > 0, "Staking: no tokens staked");

        uint256 len = tokenIds.length;
        totalStaked -= len;

        for (uint256 i; i < len; i++) {
            require(stakers[tokenIds[i]] == msg.sender, "Staking: not staker");
            delete stakers[tokenIds[i]];
            angelNFT.safeTransferFrom(address(this), msg.sender, tokenIds[i]);
        }
        delete stakedNFTs[msg.sender];

        /// claim rewards for all supported reward tokens.
        uint256 reward;
        for (uint256 i; i < rewardTokens.length; i++) {
            reward = earned(rewardTokens[i], tokenIds);
            if (reward > 0) {
                IERC20(rewardTokens[i]).safeTransfer(msg.sender, reward);
            }
        }

        _setAbortedReward(tokenIds);

        emit NFTUnstaked(tokenIds, msg.sender);
    }

    /**
     * @dev claim reward for all user staked tokens.
     * collect all of accumulated rewards in different type of tokens pool does support
     * update reward related arguments after sending reward
     * @notice emit {RewardClaimed} event
     */
    function claim() external nonReentrant {
        require(stakedNFTs[msg.sender].length > 0, "Staking: no tokens staked");

        _updateRewardConditions();

        uint256 reward;
        for (uint256 i; i < rewardTokens.length; i++) {
            reward = earned(rewardTokens[i], stakedNFTs[msg.sender]);
            if (reward > 0) {
                IERC20(rewardTokens[i]).safeTransfer(msg.sender, reward);
            }
        }

        _setAbortedReward(stakedNFTs[msg.sender]);

        emit RewardClaimed(msg.sender);
    }

    /**
     * @dev update reward related arguments after reward token arrived
     * @param token reward token address
     * @param amount reward token amounts received
     * @notice emit {RewardAdded} event
     */
    function notifyRewardAmount(
        address token,
        uint256 amount
    ) external onlyRewardDistributor {
        bool exist;
        for (uint256 i; i < rewardTokens.length; i++) {
            exist = exist || (rewardTokens[i] == token);
        }
        if (!exist) rewardTokens.push(token);

        _updateRewardConditions();

        require(amount > 0, "Staking: not enough reward tokens");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        duration[token] = duration[token] == 0
            ? DEFAULT_DURATION
            : duration[token];
        if (block.timestamp >= periodFinish[token]) {
            rewardRate[token] = amount / duration[token];
        } else {
            uint256 remaining = periodFinish[token] - block.timestamp;
            uint256 leftover = remaining * rewardRate[token];
            rewardRate[token] = (amount + leftover) / duration[token];
        }
        lastUpdateTime[token] = block.timestamp;
        periodFinish[token] = block.timestamp + duration[token];
        emit RewardAdded(token, amount, totalStaked);
    }

    /**
     * @dev update reward emitting time
     * @param token reward token address
     * @param period new emitting period
     */
    function setRewardDuration(
        address token,
        uint256 period
    ) external onlyRewardDistributor {
        _updateRewardConditions();

        require(period > 0, "Staking: not reasonable duration");
        uint256 old = duration[token];
        duration[token] = period * 24 * 60 * 60;

        if (block.timestamp < periodFinish[token]) {
            uint256 remaining = periodFinish[token] - block.timestamp;
            uint256 leftover = remaining * rewardRate[token];
            periodFinish[token] = periodFinish[token] - old + duration[token];
            require(
                block.timestamp < periodFinish[token],
                "Staking: not reasonable duration"
            );
            rewardRate[token] =
                leftover /
                (periodFinish[token] - block.timestamp);
        }
    }

    /**
     * @dev drain all leftover reward tokens after finishing rewarding.
     * if it's being under rewarding, it rejects to take out tokens.
     * @param tokens reward tokens to be taken out of contract
     */
    function drainLeftOver(
        address[] memory tokens
    ) external onlyRewardDistributor {
        uint256 pendingReward;
        uint256 balance;
        uint256 leftover;
        for (uint256 i; i < tokens.length; i++) {
            if (block.timestamp >= periodFinish[tokens[i]]) {
                pendingReward = 0;
                for (uint256 j; j < stakersArray.length; j++) {
                    pendingReward += earned(
                        tokens[i],
                        stakedNFTs[stakersArray[j]]
                    );
                }
                balance = IERC20(tokens[i]).balanceOf(address(this));
                leftover = balance - pendingReward;
                if (leftover > 0) {
                    IERC20(tokens[i]).safeTransfer(msg.sender, leftover);
                }
            }
        }
    }

    function _updateRewardConditions() internal {
        for (uint256 i; i < rewardTokens.length; i++) {
            accRewardPerNFT[rewardTokens[i]] = accumulatedRewardPerNFT(
                rewardTokens[i]
            );
            lastUpdateTime[rewardTokens[i]] = lastTimeRewardApplicable(
                rewardTokens[i]
            );
        }
    }

    function _setAbortedReward(uint256[] memory tokenIds) internal {
        for (uint256 i; i < rewardTokens.length; i++) {
            for (uint256 j; j < tokenIds.length; j++) {
                abortedRewardPerNFT[rewardTokens[i]][
                    tokenIds[j]
                ] = accRewardPerNFT[rewardTokens[i]];
            }
        }
    }
}

