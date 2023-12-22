// SPDX-License-Identifier: GNU GPLv3
pragma solidity ^0.8.0;

////////////////////////////////////////////////////////////////////////////////
//                                                                            //
//                                                                            //
//                              #@@@@@@@@@@@@&,                               //
//                      .@@@@@   .@@@@@@@@@@@@@@@@@@@*                        //
//                  %@@@,    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    //
//               @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                 //
//             @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@               //
//           *@@@#    .@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             //
//          *@@@%    &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//          @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//                                                                            //
//          (@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,           //
//          (@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,           //
//                                                                            //
//          @@@@@   @@@@@@@@@   @@@@@@@@@   @@@@@@@@@   @@@@@@@@@             //
//            &@@@@@@@    #@@@@@@@.   ,@@@@@@@,   .@@@@@@@/    @@@@           //
//                                                                            //
//          @@@@@      @@@%    *@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          @@@@@      @@@@    %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          .@@@@      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//            @@@@@  &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             //
//                (&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&(                 //
//                                                                            //
//                                                                            //
////////////////////////////////////////////////////////////////////////////////

// Libraries
import { AccessControl } from "./AccessControl.sol";
import { ERC20 } from "./ERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { ContractWhitelist } from "./ContractWhitelist.sol";

// Interfaces
import { IERC20 } from "./IERC20.sol";
import { IERC721 } from "./IERC721.sol";
import { IERC721Receiver } from "./IERC721Receiver.sol";

/// @title Umami MarinateV2 Staking
/// @author 0xtoki luffyowls
contract MarinateV2 is AccessControl, IERC721Receiver, ReentrancyGuard, ERC20, ContractWhitelist {
    using SafeERC20 for IERC20;

    /************************************************
     *  STORAGE
     ***********************************************/

    /// @notice ttal token rewards
    mapping(address => uint256) public totalTokenRewardsPerStake;

    /// @notice number of reward epochs paid to marinator
    mapping(address => mapping(address => uint256)) public paidTokenRewardsPerStake;

    /// @notice the multiplier percentage of an nft
    /// the multiplier amount for that nft collection represented as a percentage with base 10000 -> 5% = 500
    mapping(address => uint256) public nftMultiplier;

    /// @notice if the user has an nft staked
    mapping(address => mapping(address => bool)) public isNFTStaked;

    /// @notice if the token is an approved reward token
    mapping(address => bool) public isApprovedRewardToken;

    /// @notice if the token is an approved NFT for staking
    mapping(address => bool) public isApprovedMultiplierNFT;

    /// @notice the marinator info for a marinator
    mapping(address => Marinator) public marinatorInfo;

    /// @notice rewards due to be paid to marinator
    mapping(address => mapping(address => uint256)) public toBePaid;

    /// @notice an array of reward tokens to issue rewards in
    address[] public rewardTokens;

    /// @notice an array of multiplier tokens to use for multiplying the reward
    address[] public multiplierNFTs;

    /// @notice is staking enabled
    bool public stakeEnabled;

    /// @notice is nft staking enabled
    bool public multiplierStakingEnabled;

    /// @notice are withdrawals enabled
    bool public withdrawEnabled;

    /// @notice allow early withdrawals from staking multiplier
    bool public multiplierWithdrawEnabled;

    /// @notice if transfering mUMAMI is enabled
    bool public transferEnabled;

    /// @notice allow payment of rewards
    bool public payRewardsEnabled;

    /// @notice total UMAMI staked
    uint256 public totalStaked;

    /// @notice total staked taking into consideration multipliers
    uint256 public totalMultipliedStaked;

    /// @notice scale used for calcs
    uint256 public SCALE;

    /// @notice deposit upper limit
    uint256 public depositLimit;

    /************************************************
     *  IMMUTABLES & CONSTANTS
     ***********************************************/

    /// @notice the admin role hash
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice for base calculations
    uint256 public constant BASE = 10000;

    /// @notice address of the UMAMI token
    address public immutable UMAMI;

    /************************************************
     *  STRUCTS
     ***********************************************/

    struct Marinator {
        uint256 amount;
        uint256 multipliedAmount;
    }

    /************************************************
     *  EVENTS
     ***********************************************/

    event Stake(address addr, uint256 amount, uint256 multipliedAmount);
    event StakeMultiplier(address addr, address nft, uint256 tokenId, uint256 multipliedAmount);
    event Withdraw(address addr, uint256 amount);
    event WithdrawMultiplier(address addr, address nft, uint256 tokenId, uint256 multipliedAmount);
    event RewardCollection(address token, address addr, uint256 amount);
    event RewardAdded(address token, uint256 amount, uint256 rps);
    event RewardClaimed(address token, address staker, uint256 amount);

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(
        address _UMAMI,
        string memory name,
        string memory symbol,
        uint256 _depositLimit
    ) ERC20(name, symbol) {
        UMAMI = _UMAMI;
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        rewardTokens.push(_UMAMI);
        isApprovedRewardToken[_UMAMI] = true;
        stakeEnabled = true;
        multiplierStakingEnabled = true;
        withdrawEnabled = false;
        multiplierWithdrawEnabled = false;
        transferEnabled = true;
        payRewardsEnabled = true;
        depositLimit = _depositLimit;
        totalStaked = 0;
        totalMultipliedStaked = 0;
        SCALE = 1e40;
    }

    /************************************************
     *  DEPOSIT & WITHDRAW
     ***********************************************/

    /**
     * @notice stake a multiplier nft
     * @param nft the address of the NFT contract
     * @param tokenId the tokenId of the nft to stake
     */
    function stakeMultiplier(address nft, uint256 tokenId) external isEligibleSender {
        require(multiplierStakingEnabled, "NFT staking not enabled");
        require(isApprovedMultiplierNFT[nft], "Unapproved NFT");
        require(!isNFTStaked[msg.sender][nft], "NFT already staked");

        // stake nft multiplier
        IERC721(nft).safeTransferFrom(msg.sender, address(this), tokenId);
        isNFTStaked[msg.sender][nft] = true;

        // update existing marinated amount
        Marinator memory info = marinatorInfo[msg.sender];
        uint256 newMultipliedAmount = _getMultipliedAmount(info.amount, msg.sender);

        // update marinator info
        marinatorInfo[msg.sender] = Marinator({ amount: info.amount, multipliedAmount: newMultipliedAmount });

        // update totals
        totalMultipliedStaked -= info.multipliedAmount;
        totalMultipliedStaked += newMultipliedAmount;

        // store the sender's info
        emit StakeMultiplier(msg.sender, nft, tokenId, newMultipliedAmount);
    }

    /**
     * @notice withdraw a multiplier nft
     * @param nft the address of the NFT contract
     * @param tokenId the tokenId of the nft to stake
     */
    function withdrawMultiplier(address nft, uint256 tokenId) external {
        require(multiplierWithdrawEnabled, "Withdraw not enabled");
        require(isApprovedMultiplierNFT[nft], "Unapproved NFT");
        require(isNFTStaked[msg.sender][nft], "NFT not staked");

        Marinator memory info = marinatorInfo[msg.sender];

        isNFTStaked[msg.sender][nft] = false;
        IERC721(nft).safeTransferFrom(address(this), msg.sender, tokenId);

        uint256 newMultipliedAmount = _getMultipliedAmount(info.amount, msg.sender);

        // update existing marinated amount
        marinatorInfo[msg.sender] = Marinator({ amount: info.amount, multipliedAmount: newMultipliedAmount });

        // update totals
        totalMultipliedStaked -= info.multipliedAmount;
        totalMultipliedStaked += newMultipliedAmount;

        emit WithdrawMultiplier(msg.sender, nft, tokenId, newMultipliedAmount);
    }

    /**
     * @notice stake UMAMI
     * @param amount the amount of umami to stake
     */
    function stake(uint256 amount) external isEligibleSender {
        require(stakeEnabled, "Staking not enabled");
        require(amount > 0, "Invalid stake amount");
        require(totalStaked < depositLimit, "Deposit capacity reached");

        Marinator memory info = marinatorInfo[msg.sender];
        if (info.amount == 0) {
            // new user - not eligible for any previous rewards on any token
            _resetPaidRewards(msg.sender);
        } else {
            _collectRewards(msg.sender);
        }

        IERC20(UMAMI).safeTransferFrom(msg.sender, address(this), amount);
        _mint(msg.sender, amount);

        uint256 multipliedAmount = _getMultipliedAmount(amount, msg.sender);

        // store the sender's info
        marinatorInfo[msg.sender] = Marinator({
            amount: info.amount + amount,
            multipliedAmount: info.multipliedAmount + multipliedAmount
        });

        totalStaked += amount;
        totalMultipliedStaked += multipliedAmount;
        emit Stake(msg.sender, amount, multipliedAmount);
    }

    /**
     * @notice withdraw staked UMAMI and burn mUMAMI
     */
    function withdraw() public nonReentrant {
        require(withdrawEnabled, "Withdraw not enabled");
        Marinator memory info = marinatorInfo[msg.sender];
        require(info.multipliedAmount > 0, "No staked balance");

        _collectRewards(msg.sender);
        _payRewards(msg.sender);

        delete marinatorInfo[msg.sender];
        totalMultipliedStaked -= info.multipliedAmount;
        totalStaked -= info.amount;

        IERC20(UMAMI).safeTransfer(msg.sender, info.amount);
        _burn(msg.sender, info.amount);

        emit Withdraw(msg.sender, info.amount);
    }

    /************************************************
     *  REWARDS
     ***********************************************/

    /**
     * @notice claim rewards
     */
    function claimRewards() public nonReentrant {
        _collectRewards(msg.sender);
        _payRewards(msg.sender);
    }

    /**
     * @notice adds a reward token amount
     * @param token the token address of the reward
     * @param amount the amount of the token
     */
    function addReward(address token, uint256 amount) external nonReentrant {
        require(isApprovedRewardToken[token], "Token is not approved");
        require(totalMultipliedStaked > 0, "Total multiplied staked zero");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 rewardPerStake = (amount * SCALE) / totalMultipliedStaked;
        require(rewardPerStake > 0, "Insufficient reward per stake");
        totalTokenRewardsPerStake[token] += rewardPerStake;
        emit RewardAdded(token, amount, rewardPerStake);
    }

    /**
     * @notice pay rewards to a marinator
     */
    function _payRewards(address user) private {
        require(payRewardsEnabled, "Pay rewards disabled");
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 amount = toBePaid[token][user];
            IERC20(token).safeTransfer(user, amount);
            emit RewardClaimed(token, user, amount);
            delete toBePaid[token][user];
        }
    }

    /**
     * @notice reset rewards for user
     * @param user the user to reset rewards paid for
     */
    function _resetPaidRewards(address user) private {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            paidTokenRewardsPerStake[token][user] = totalTokenRewardsPerStake[token];
        }
    }

    /**
     * @notice collect rewards from a marinator
     * @param user the amount of umami to stake
     */
    function _collectRewards(address user) private {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            _collectRewardsForToken(rewardTokens[i], user);
        }
    }

    /**
     * @notice collect rewards for a token
     * @param token the token to collect rewards for
     * @param user the amount of umami to stake
     */
    function _collectRewardsForToken(address token, address user) private {
        Marinator memory info = marinatorInfo[user];
        if (info.multipliedAmount > 0) {
            uint256 owedPerUnitStake = totalTokenRewardsPerStake[token] - paidTokenRewardsPerStake[token][user];
            uint256 totalRewards = (info.multipliedAmount * owedPerUnitStake) / SCALE;
            paidTokenRewardsPerStake[token][user] = totalTokenRewardsPerStake[token];
            toBePaid[token][user] += totalRewards;
        }
    }

    /************************************************
     *  MUTATORS
     ***********************************************/

    /**
     * @notice add an approved reward token to be paid
     * @param token the address of the token to be paid in
     */
    function addApprovedRewardToken(address token) external onlyAdmin {
        require(!isApprovedRewardToken[token], "Reward token exists");
        isApprovedRewardToken[token] = true;
        rewardTokens.push(token);
    }

    /**
     * @notice remove a reward token
     * @param token the address of the token to remove
     */
    function removeApprovedRewardToken(address token) external onlyAdmin {
        require(isApprovedRewardToken[token], "Reward token does not exist");
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] == token) {
                rewardTokens[i] = rewardTokens[rewardTokens.length - 1];
                rewardTokens.pop();
                isApprovedRewardToken[token] = false;
            }
        }
    }

    /**
     * @notice add an nft multiplier token
     * @param token the address of the token to add
     * @param multiplier the multiplier amount for that nft collection represented as a percentaage with base 10000
     * eg. a multiplier of 500 will be 5%
     */
    function addApprovedMultiplierToken(address token, uint256 multiplier) external onlyAdmin {
        require(!isApprovedMultiplierNFT[token], "Approved NFT exists");
        isApprovedMultiplierNFT[token] = true;
        nftMultiplier[token] = multiplier;
        multiplierNFTs.push(token);
    }

    /**
     * @notice remove a nft multiplier token
     * @param token the address of the token to remove
     */
    function removeApprovedMultiplierToken(address token) external onlyAdmin {
        require(isApprovedMultiplierNFT[token], "Approved NFT does not exist");
        for (uint256 i = 0; i < multiplierNFTs.length; i++) {
            if (multiplierNFTs[i] == token) {
                multiplierNFTs[i] = multiplierNFTs[multiplierNFTs.length - 1];
                multiplierNFTs.pop();
                isApprovedMultiplierNFT[token] = false;
            }
        }
    }

    /**
     * @notice set the scale
     * @param _scale scale
     */
    function setScale(uint256 _scale) external onlyAdmin {
        SCALE = _scale;
    }

    /**
     * @notice set staking enabled
     * @param enabled enabled
     */
    function setStakeEnabled(bool enabled) external onlyAdmin {
        stakeEnabled = enabled;
    }

    /**
     * @notice set multiplier staking enabled
     * @param enabled enabled
     */
    function setMultiplierStakeEnabled(bool enabled) external onlyAdmin {
        multiplierStakingEnabled = enabled;
    }

    /**
     * @notice set withdrawal enabled
     * @param enabled enabled
     */
    function setStakingWithdrawEnabled(bool enabled) external onlyAdmin {
        withdrawEnabled = enabled;
    }

    /**
     * @notice set multiplier withdrawal enabled
     * @param enabled enabled
     */
    function setMultiplierWithdrawEnabled(bool enabled) external onlyAdmin {
        multiplierWithdrawEnabled = enabled;
    }

    /**
     * @notice set transfer enabled
     * @param enabled enabled
     */
    function setTransferEnabled(bool enabled) external onlyAdmin {
        transferEnabled = enabled;
    }

    /**
     * @notice set pay rewards enabled
     * @param enabled enabled
     */
    function setPayRewardswEnabled(bool enabled) external onlyAdmin {
        payRewardsEnabled = enabled;
    }

    /**
     * @notice set deposit limit
     * @param limit upper limit for deposits
     */
    function setDepositLimit(uint256 limit) external onlyAdmin {
        depositLimit = limit;
    }

    /************************************************
     *  VIEWS
     ***********************************************/

    /**
     * @notice get the multiplied amount of total share
     * @param amount the unmultiplied amount
     * @return multipliedAmount the reward amount considering the multiplier nft's the user has staked
     */
    function _getMultipliedAmount(uint256 amount, address account) private view returns (uint256 multipliedAmount) {
        if (!isWhitelisted(account)) {
            return 0;
        }
        uint256 multiplier = BASE;
        for (uint256 i = 0; i < multiplierNFTs.length; i++) {
            if (isNFTStaked[account][multiplierNFTs[i]]) {
                multiplier += nftMultiplier[multiplierNFTs[i]];
            }
        }
        multipliedAmount = (amount * SCALE * multiplier) / BASE;
    }

    /**
     * @notice get the available token rewards
     * @param staker the marinator
     * @param token the token to check for
     * @return totalRewards - the available rewards for that token and marinator
     */
    function getAvailableTokenRewards(address staker, address token) external view returns (uint256 totalRewards) {
        Marinator memory info = marinatorInfo[staker];
        uint256 owedPerUnitStake = totalTokenRewardsPerStake[token] - paidTokenRewardsPerStake[token][staker];
        uint256 pendingRewards = (info.multipliedAmount * owedPerUnitStake) / SCALE;
        totalRewards = pendingRewards + toBePaid[token][staker];
    }

    /************************************************
     *  ERC20 OVERRIDES
     ***********************************************/

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal virtual override {
        require(transferEnabled, "Transfer disabled");
        if (from == address(0) || to == address(0)) {
            return;
        } else {
            Marinator memory info = marinatorInfo[to];
            if (info.amount == 0) {
                _resetPaidRewards(to);
            }
            if (isWhitelisted(from)) {
                _collectRewards(from);
            }
            if (isWhitelisted(to)) {
                _collectRewards(to);
            }
        }
    }

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256
    ) internal virtual override {
        if (from == address(0) || to == address(0)) {
            return;
        } else {
            uint256 fromBalance = balanceOf(from);
            uint256 toBalance = balanceOf(to);
            Marinator memory marinatorFrom = marinatorInfo[from];
            Marinator memory marinatorTo = marinatorInfo[to];

            // get new multiplied amounts
            uint256 multipliedFromAmount = _getMultipliedAmount(fromBalance, from);
            uint256 multipliedToAmount = _getMultipliedAmount(toBalance, to);

            // calculate total old multiplied amounts
            uint256 oldMultipliedAmount = marinatorFrom.multipliedAmount + marinatorTo.multipliedAmount;
            uint256 newMultipliedAmount = multipliedFromAmount + multipliedToAmount;

            // calculate new total multiplied staked
            if (isWhitelisted(from) && isWhitelisted(to)) {
                totalMultipliedStaked -= oldMultipliedAmount;
                totalMultipliedStaked += newMultipliedAmount;
            } else {
                if (!isWhitelisted(to)) {
                    totalMultipliedStaked -= marinatorFrom.multipliedAmount;
                    totalMultipliedStaked += multipliedFromAmount;
                }
                if (!isWhitelisted(from)) {
                    totalMultipliedStaked -= marinatorTo.multipliedAmount;
                    totalMultipliedStaked += multipliedToAmount;
                }
            }
            // update marinator info
            marinatorInfo[from] = Marinator({ amount: fromBalance, multipliedAmount: multipliedFromAmount });
            marinatorInfo[to] = Marinator({ amount: toBalance, multipliedAmount: multipliedToAmount });
        }
    }

    /************************************************
     *  ERC721 HANDLERS
     ***********************************************/

    /**
     * @notice ERC721 transfer
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return MarinateV2.onERC721Received.selector;
    }

    /************************************************
     *  ADMIN
     ***********************************************/

    /**
     * @notice migrate a token to a different address
     * @param token the token address
     * @param destination the token destination
     * @param amount the token amount
     */
    function migrateToken(
        address token,
        address destination,
        uint256 amount
    ) external onlyAdmin {
        uint256 total = 0;
        if (amount == 0) {
            total = IERC20(token).balanceOf(address(this));
        } else {
            total = amount;
        }
        IERC20(token).safeTransfer(destination, total);
    }

    /**
     * @notice recover eth
     */
    function recoverEth() external onlyAdmin {
        (bool success, ) = msg.sender.call{ value: address(this).balance }("");
        require(success, "Withdraw failed");
    }

    /************************************************
     *  MODIFIERS
     ***********************************************/

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "Caller is not an admin");
        _;
    }
}

