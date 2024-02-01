// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./Math.sol";
import "./ERC20.sol";
import "./introspection_IERC165.sol";
import "./ABDKMath64x64.sol";
import "./IStakingToken.sol";
import "./IRankedMintingToken.sol";
import "./IBurnableToken.sol";
import "./IBurnRedeemable.sol";
import "./Ownable.sol";
import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract YENCrypto is Context, IRankedMintingToken, IStakingToken, IBurnableToken, Ownable, ERC20("YEN Crypto", "YEN") {
    using Math for uint256;
    using ABDKMath64x64 for int128;
    using ABDKMath64x64 for uint256;
    using SafeERC20 for IERC20;

    // INTERNAL TYPE TO DESCRIBE A YEN MINT INFO
    struct MintInfo {
        address user;
        uint256 term;
        uint256 maturityTs;
        uint256 rank;
        uint256 amplifier;
        uint256 eaaRate;
    }

    // INTERNAL TYPE TO DESCRIBE A YEN STAKE
    struct StakeInfo {
        uint256 term;
        uint256 maturityTs;
        uint256 amount;
        uint256 apy;
    }

    uint256 public startTime;
    address public FundAddress;
    // PUBLIC CONSTANTS

    uint256 public constant SECONDS_IN_DAY = 3_600 * 24;
    uint256 public constant DAYS_IN_YEAR = 365;

    uint256 public constant GENESIS_RANK = 1;

    uint256 public constant MIN_TERM = 1 * SECONDS_IN_DAY - 1;
    uint256 public constant MAX_TERM_START = 100 * SECONDS_IN_DAY;
    uint256 public constant MAX_TERM_END = 1_000 * SECONDS_IN_DAY;
    uint256 public constant TERM_AMPLIFIER = 15;
    uint256 public constant TERM_AMPLIFIER_THRESHOLD = 5_000;
    uint256 public constant REWARD_AMPLIFIER_START = 100;
    uint256 public constant REWARD_AMPLIFIER_END = 1;
    uint256 public constant EAA_PM_START = 10;
    uint256 public constant EAA_PM_STEP = 1;
    uint256 public constant EAA_RANK_STEP = 100_000;
    uint256 public constant WITHDRAWAL_WINDOW_DAYS = 7;
    uint256 public constant MAX_PENALTY_PCT = 99;

    uint256 public constant YEN_MIN_STAKE = 0;

    uint256 public constant YEN_MIN_BURN = 0;

    uint256 public constant YEN_APY_START = 20;
    uint256 public constant YEN_APY_DAYS_STEP = 90;
    uint256 public constant YEN_APY_END = 2;

    // PUBLIC STATE, READABLE VIA NAMESAKE GETTERS

    uint256 public immutable genesisTs;
    uint256 public globalRank = GENESIS_RANK;
    uint256 public activeMinters;
    uint256 public totalTransactions;
    // user address => YEN mint info
    mapping(address => MintInfo) public userMints;
    // user address => YEN stake info
    mapping(address => StakeInfo) public userStakes;
    // user address => YEN burn amount
    mapping(address => uint256) public userBurns;

    // CONSTRUCTOR
    constructor(uint256 _startTime, address _FundAddress) {
        genesisTs = block.timestamp;
        startTime = _startTime;
        FundAddress = _FundAddress;
    }

    modifier chargeFee(){
        require(msg.value >= 0.005 ether, "insufficient fee");
        payable(FundAddress).transfer(msg.value);
        _;
    }

    // PRIVATE METHODS

    /**
     * @dev calculates current MaxTerm based on Global Rank
     *      (if Global Rank crosses over TERM_AMPLIFIER_THRESHOLD)
     */
    function _calculateMaxTerm() private view returns (uint256) {
        if (globalRank > TERM_AMPLIFIER_THRESHOLD) {
            uint256 delta = globalRank.fromUInt().log_2().mul(TERM_AMPLIFIER.fromUInt()).toUInt();
            uint256 newMax = MAX_TERM_START + delta * SECONDS_IN_DAY;
            return Math.min(newMax, MAX_TERM_END);
        }
        return MAX_TERM_START;
    }

    /**
     * @dev calculates Withdrawal Penalty depending on lateness
     */
    function _penalty(uint256 secsLate) private pure returns (uint256) {
        // =MIN(2^(daysLate+3)/window-1,99)
        uint256 daysLate = secsLate / SECONDS_IN_DAY;
        if (daysLate > WITHDRAWAL_WINDOW_DAYS - 1) return MAX_PENALTY_PCT;
        uint256 penalty = (uint256(1) << (daysLate + 3)) / WITHDRAWAL_WINDOW_DAYS - 1;
        return Math.min(penalty, MAX_PENALTY_PCT);
    }

    /**
     * @dev calculates net Mint Reward (adjusted for Penalty)
     */
    function _calculateMintReward(
        uint256 cRank,
        uint256 term,
        uint256 maturityTs,
        uint256 amplifier,
        uint256 eeaRate
    ) private view returns (uint256) {
        uint256 secsLate = block.timestamp - maturityTs;
        uint256 penalty = _penalty(secsLate);
        uint256 rankDelta = Math.max(globalRank - cRank, 2);
        uint256 EAA = (1_000 + eeaRate);
        uint256 reward = getGrossReward(rankDelta, amplifier, term, EAA);
        return (reward * (100 - penalty)) / 100;
    }

    /**
     * @dev cleans up User Mint storage (gets some Gas credit;))
     */
    function _cleanUpUserMint() private {
        delete userMints[_msgSender()];
        activeMinters--;
    }

    /**
     * @dev calculates Reward Amplifier
     */
    function _calculateRewardAmplifier() private view returns (uint256) {
        uint256 amplifierDecrease = (block.timestamp - genesisTs) / SECONDS_IN_DAY;
        if (amplifierDecrease < REWARD_AMPLIFIER_START) {
            return Math.max(REWARD_AMPLIFIER_START - amplifierDecrease, REWARD_AMPLIFIER_END);
        } else {
            return REWARD_AMPLIFIER_END;
        }
    }

    /**
     * @dev calculates Early Adopter Amplifier Rate (in 1/000ths)
     *      actual EAA is (1_000 + EAAR) / 1_000
     */
    function _calculateEAARate() private view returns (uint256) {
        uint256 decrease = (EAA_PM_STEP * globalRank) / EAA_RANK_STEP;
        if (decrease > EAA_PM_START) return 0;
        return EAA_PM_START - decrease;
    }

    /**
     * @dev calculates APY (in %)
     */
    function _calculateAPY() private view returns (uint256) {
        uint256 decrease = (block.timestamp - genesisTs) / (SECONDS_IN_DAY * YEN_APY_DAYS_STEP);
        if (YEN_APY_START - YEN_APY_END < decrease) return YEN_APY_END;
        return YEN_APY_START - decrease;
    }


    // PUBLIC CONVENIENCE GETTERS

    /**
     * @dev calculates gross Mint Reward
     */
    function getGrossReward(
        uint256 rankDelta,
        uint256 amplifier,
        uint256 term,
        uint256 eaa
    ) public pure returns (uint256) {
        int128 log128 = rankDelta.fromUInt().log_2();
        int128 reward128 = log128.mul(amplifier.fromUInt()).mul(term.fromUInt()).mul(eaa.fromUInt());
        return reward128.div(uint256(1_000).fromUInt()).toUInt();
    }

    /**
     * @dev returns User Mint object associated with User account address
     */
    function getUserMint() external view returns (MintInfo memory) {
        return userMints[_msgSender()];
    }

    /**
     * @dev returns YEN Stake object associated with User account address
     */
    function getUserStake() external view returns (StakeInfo memory) {
        return userStakes[_msgSender()];
    }

    /**
     * @dev returns current AMP
     */
    function getCurrentAMP() external view returns (uint256) {
        return _calculateRewardAmplifier();
    }

    /**
     * @dev returns current EAA Rate
     */
    function getCurrentEAAR() external view returns (uint256) {
        return _calculateEAARate();
    }

    /**
     * @dev returns current APY
     */
    function getCurrentAPY() external view returns (uint256) {
        return _calculateAPY();
    }

    /**
     * @dev returns current MaxTerm
     */
    function getCurrentMaxTerm() external view returns (uint256) {
        return _calculateMaxTerm();
    }

    // PUBLIC STATE-CHANGING METHODS

    /**
     * @dev accepts User cRank claim provided all checks pass (incl. no current claim exists)
     */
    function claimRank(uint256 term) payable external chargeFee{
        uint256 termSec = term * SECONDS_IN_DAY;
        require(termSec > MIN_TERM, "CRank: Term less than min");
        require(termSec < _calculateMaxTerm() + 1, "CRank: Term more than current max term");
        require(userMints[_msgSender()].rank == 0, "CRank: Mint already in progress");

        // create and store new MintInfo
        MintInfo memory mintInfo = MintInfo({
        user : _msgSender(),
        term : term,
        maturityTs : block.timestamp + termSec,
        rank : globalRank,
        amplifier : _calculateRewardAmplifier(),
        eaaRate : _calculateEAARate()
        });
        userMints[_msgSender()] = mintInfo;
        activeMinters++;
        totalTransactions++;
        emit RankClaimed(_msgSender(), term, globalRank++);
    }

    /**
     * @dev ends minting upon maturity (and within permitted Withdrawal Time Window), gets minted YEN
     */
    function claimMintReward()  external {
        MintInfo memory mintInfo = userMints[_msgSender()];
        require(mintInfo.rank > 0, "CRank: No mint exists");
        require(block.timestamp > mintInfo.maturityTs, "CRank: Mint maturity not reached");

        // calculate reward and mint tokens
        uint256 rewardAmount = _calculateMintReward(
            mintInfo.rank,
            mintInfo.term,
            mintInfo.maturityTs,
            mintInfo.amplifier,
            mintInfo.eaaRate
        ) * 1 ether;
        _mint(_msgSender(), rewardAmount);

        _cleanUpUserMint();
        totalTransactions++;
        emit MintClaimed(_msgSender(), rewardAmount);
    }

    /**
     * @dev  ends minting upon maturity (and within permitted Withdrawal time Window)
     *       mints YEN coins and splits them between User and designated other address
     */
    function claimMintRewardAndShare(address other, uint256 pct) external{
        MintInfo memory mintInfo = userMints[_msgSender()];
        require(other != address(0), "CRank: Cannot share with zero address");
        require(pct > 0, "CRank: Cannot share zero percent");
        require(pct < 101, "CRank: Cannot share 100+ percent");
        require(mintInfo.rank > 0, "CRank: No mint exists");
        require(block.timestamp > mintInfo.maturityTs, "CRank: Mint maturity not reached");

        // calculate reward
        uint256 rewardAmount = _calculateMintReward(
            mintInfo.rank,
            mintInfo.term,
            mintInfo.maturityTs,
            mintInfo.amplifier,
            mintInfo.eaaRate
        ) * 1 ether;
        uint256 sharedReward = (rewardAmount * pct) / 100;
        uint256 ownReward = rewardAmount - sharedReward;

        // mint reward tokens
        _mint(_msgSender(), ownReward);
        _mint(other, sharedReward);

        _cleanUpUserMint();
        totalTransactions++;
        emit MintClaimed(_msgSender(), rewardAmount);
    }


    /**
     * @dev burns YEN tokens and creates Proof-Of-Burn record to be used by connected DeFi services
     */
    function burn(address user, uint256 amount) public {
        require(amount > YEN_MIN_BURN, "Burn: Below min limit");
        require(
            IERC165(_msgSender()).supportsInterface(type(IBurnRedeemable).interfaceId),
            "Burn: not a supported contract"
        );

        _spendAllowance(user, _msgSender(), amount);
        _burn(user, amount);
        userBurns[user] += amount;
        IBurnRedeemable(_msgSender()).onTokenBurned(user, amount);
        totalTransactions++;
    }

    function updateStartTime(uint256 _startTime) external onlyOwner {
        startTime = _startTime;
    }

    //in case of mis-transfer tokens
    function recovery(address erc20Token, uint256 amount) external onlyOwner {
        require(erc20Token != address(this), "can not transfer yen");

        if (erc20Token != address(0)) {
            IERC20(erc20Token).safeTransfer(msg.sender, amount);
        } else {
            Address.sendValue(payable(msg.sender), amount);
        }
    }
}

