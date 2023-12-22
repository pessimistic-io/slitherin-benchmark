// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./ReentrancyGuardUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Ownable2StepUpgradeable.sol";
import "./EnumerableSet.sol";
import "./SafeERC20.sol";

import "./VeERC20Upgradeable.sol";

import "./Math.sol";
import "./Checker.sol";

import "./ISavvyPositionManager.sol";
import "./ISavvyBooster.sol";
import "./IVeSvy.sol";
import "./IAllowlist.sol";
import "./Errors.sol";

/// @title VeSvy
/// @notice The staking contract for SVY, as well as the token used for governance.
/// Note Venom does not seem to hurt the Savvy, it only makes it stronger.
/// Allows stake/unstake of svy
/// Here are the rules of the game:
/// If you stake svy, you generate veSvy at the current `generationRate` until you reach `maxCap`
/// If you unstake any amount of svy, you loose all of your veSvy.
/// ERC721 staking does not affect generation nor cap for the moment, but it will in a future upgrade.
/// Note that it's ownable and the owner wields tremendous power. The ownership
/// will be transferred to a governance smart contract once Savvy is sufficiently
/// distributed and the community can show to govern itself.
contract VeSvy is
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    VeERC20Upgradeable,
    IVeSvy
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserInfo {
        uint256 amount; // svy staked by user
        uint256 lastRelease; // time of last veSvy claim or first deposit if user has not claimed yet
    }

    /// @notice The handle of SavvyBooster
    ISavvyBooster public savvyBooster;

    /// @notice the svy token
    IERC20 public svy;

    /// @dev Magic value for onERC721Received
    /// Equals to bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))
    bytes4 private constant ERC721_RECEIVED = 0x150b7a02;

    /// @notice max veSvy to staked svy ratio
    /// Note if user has 10 svy staked, they can only have a max of 10 * maxCap veSvy in balance
    uint256 public maxCap;

    /// @notice the rate of veSvy generated per second, per svy staked
    uint256 public generationRate;

    /// @notice invVvoteThreshold threshold.
    /// @notice voteThreshold is the percentage of cap from which votes starts to count for governance proposals.
    /// @dev inverse of the threshold to apply.
    /// Example: th = 5% => (1/5) * 100 => invVoteThreshold = 20
    /// Example 2: th = 3.03% => (1/3.03) * 100 => invVoteThreshold = 33
    /// Formula is invVoteThreshold = (1 / th) * 100
    uint256 public invVoteThreshold;

    /// @notice allowlist wallet checker
    /// @dev contract addresses are by default unable to stake svy, they must be previously allowlisted to stake svy
    IAllowlist public allowlist;

    /// @notice user info mapping
    mapping(address => UserInfo) public users;

    /// @notice the time that veSVY starts accruing
    uint256 public veSVYAccrueStartTime;

    /// @notice events describing staking, unstaking and claiming
    event Staked(address indexed sender, address indexed user, uint256 indexed amount);
    event Unstaked(address indexed user, uint256 indexed amount);
    event Claimed(address indexed user, uint256 indexed amount);

    /// @notice asserts addres in param is not a smart contract.
    /// @notice if it is a smart contract, check that it is allowlisted
    modifier onlyAllowlisted() {
        address sender = msg.sender;
        if (sender != tx.origin) {
            Checker.checkArgument(
                address(allowlist) != address(0) && allowlist.isAllowed(sender),
                "Smart contract depositors not allowed"
            );
        }
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 _svy, uint256 _veSVYAccrueStartTime) public initializer {
        Checker.checkArgument(address(_svy) != address(0), "zero address");

        // Initialize veSVY
        __ERC20_init("Savvy Vote Escrow", "veSVY");
        __Ownable_init();
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();

        // set generationRate (veSvy per sec per svy staked)
        generationRate = 3888888888888;

        // set maxCap
        maxCap = 100;

        // set inv vote threshold
        // invVoteThreshold = 20 => th = 5
        invVoteThreshold = 20;

        // set svy
        svy = _svy;

        // set veSVY accrue start time
        veSVYAccrueStartTime = _veSVYAccrueStartTime;
    }

    /**
     * @dev pause pool, restricting certain operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev unpause pool, enabling certain operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Update savvyBooster handle with new one.
    /// @param savvyBooster_ The new handle of savvyBooster
    function setSavvyBooster(ISavvyBooster savvyBooster_) external onlyOwner {
        Checker.checkArgument(
            address(savvyBooster_) != address(0),
            "zero savvy booster contract address"
        );
        savvyBooster = savvyBooster_;
    }

    /// @notice sets allowlist address
    /// @param _allowlist the new allowlist address
    function setAllowlist(IAllowlist _allowlist) external onlyOwner {
        Checker.checkArgument(
            address(_allowlist) != address(0),
            "zero address"
        );
        allowlist = _allowlist;
    }

    /// @notice sets maxCap
    /// @param _maxCap the new max ratio
    function setMaxCap(uint256 _maxCap) external onlyOwner {
        Checker.checkArgument(_maxCap != 0, "max cap cannot be zero");
        maxCap = _maxCap;
    }

    /// @notice sets generation rate
    /// @param _generationRate the new max ratio
    function setGenerationRate(uint256 _generationRate) external onlyOwner {
        Checker.checkArgument(
            _generationRate != 0,
            "generation rate cannot be zero"
        );
        generationRate = _generationRate;
    }

    /// @notice sets invVoteThreshold
    /// @param _invVoteThreshold the new var
    /// Formula is invVoteThreshold = (1 / th) * 100
    function setInvVoteThreshold(uint256 _invVoteThreshold) external onlyOwner {
        // onwner should set a high value if we do not want to implement an important threshold
        Checker.checkArgument(
            _invVoteThreshold != 0,
            "invVoteThreshold cannot be zero"
        );
        invVoteThreshold = _invVoteThreshold;
    }

    /// @notice sets veSVYAccrueStartTime
    /// @param _veSVYAccrueStartTime the future time that veSVY should start accruing
    function setVeSVYAccrueStartTime(uint256 _veSVYAccrueStartTime) external onlyOwner {
        Checker.checkArgument(
            _veSVYAccrueStartTime > block.timestamp,
            "veSVY accrue start time must be in the future"
        );
        veSVYAccrueStartTime = _veSVYAccrueStartTime;
    }

    /// @notice checks wether user _addr has svy staked
    /// @param _addr the user address to check
    /// @return true if the user has svy in stake, false otherwise
    function isUser(address _addr) public view override returns (bool) {
        return users[_addr].amount > 0;
    }

    /// @notice returns staked amount of svy for user
    /// @param _addr the user address to check
    /// @return staked amount of svy
    function getStakedSvy(
        address _addr
    ) external view override returns (uint256) {
        return users[_addr].amount;
    }

    /// @dev explicity override multiple inheritance
    function totalSupply()
        public
        view
        override(VeERC20Upgradeable, IVeERC20)
        returns (uint256)
    {
        return super.totalSupply();
    }

    /// @dev explicity override multiple inheritance
    function balanceOf(
        address account
    ) public view override(VeERC20Upgradeable, IVeERC20) returns (uint256) {
        return super.balanceOf(account);
    }

    /// @notice deposits SVY into contract
    /// @param _amount the amount of svy to deposit
    function stake(
        uint256 _amount
    ) external override nonReentrant whenNotPaused onlyAllowlisted {
        _stake(msg.sender, _amount);
    }

    /// @notice deposits SVY into someone's position. the staker 
    /// will not be able to unstake this amount later. This acts
    /// as a transfer.
    /// @param _recipient the receiver of the staked SVY
    /// @param _amount the amount of svy to deposit
    function stakeFor(
        address _recipient,
        uint256 _amount
    ) external override nonReentrant whenNotPaused onlyAllowlisted {
        _stake(_recipient, _amount);
    }

    /// @notice claims accumulated veSVY
    function claim() external override nonReentrant whenNotPaused {
        Checker.checkState(isUser(msg.sender), "user has no stake");
        _claim(msg.sender);
    }

    /// @dev private claim function
    /// @param _addr the address of the user to claim from
    function _claim(address _addr) internal {
        uint256 amount = _claimable(_addr);

        // update last release time
        users[_addr].lastRelease = block.timestamp;

        if (amount > 0) {
            emit Claimed(_addr, amount);
            _mint(_addr, amount);
            _updateFactor(_addr);
        }
    }

    /// @notice Calculate the amount of veSVY that can be claimed by user
    /// @param _addr the address to check
    /// @return amount of veSVY that can be claimed by user
    function claimable(address _addr) external view returns (uint256) {
        require(_addr != address(0), "Not a valid address");
        return _claimable(_addr);
    }

    /// @notice Get the maximum earnable veSVY.
    /// @param _addr the address to check.
    /// @return maxVeSVYEarnable the maximum veSVY that `_addr` can earn.
    function getMaxVeSVYEarnable(
        address _addr
    ) external view override returns (uint256 maxVeSVYEarnable) {
        UserInfo storage user = users[_addr];
        maxVeSVYEarnable = user.amount * maxCap;
    }

    /// @notice Get the per second earn rate for an account.
    /// @param _addr the address to check.
    /// @return veSVYEarnRatePerSec the per second earn rate for `_addr`.
    function getVeSVYEarnRatePerSec(
        address _addr
    ) external view override returns (uint256 veSVYEarnRatePerSec) {
        UserInfo storage user = users[_addr];
        uint256 lastRelease = Math.max(user.lastRelease, veSVYAccrueStartTime);
        if (lastRelease > block.timestamp) return 0;
        uint256 secondsElapsed = block.timestamp - lastRelease;
        if (secondsElapsed == 0) return 0;
        uint256 claimableAmount = _claimable(_addr);
        veSVYEarnRatePerSec = claimableAmount / secondsElapsed;
    }

    /// @dev private claim function
    /// @param _addr the address of the user to claim from
    function _claimable(address _addr) internal view returns (uint256) {
        UserInfo storage user = users[_addr];

        // get the user's last release or veSVY accrue start time, 
        // whichever is later.
        uint256 lastRelease = Math.max(user.lastRelease, veSVYAccrueStartTime);

        if (lastRelease > block.timestamp) {
            // return 0 if last release is in the future 
            return 0;
        }

        // get seconds elapsed since last claim
        uint256 secondsElapsed = block.timestamp - lastRelease;

        // calculate pending amount
        // Math.mwmul used to multiply wad numbers
        uint256 pending = Math.wmul(
            user.amount,
            secondsElapsed * generationRate
        );

        // get user's veSVY balance
        uint256 userVeSvyBalance = balanceOf(_addr);

        // user veSVY balance cannot go above user.amount * maxCap
        uint256 maxVeSvyCap = user.amount * maxCap;

        // first, check that user hasn't reached the max limit yet
        if (userVeSvyBalance < maxVeSvyCap) {
            // then, check if pending amount will make user balance overpass maximum amount
            if ((userVeSvyBalance + pending) > maxVeSvyCap) {
                return maxVeSvyCap - userVeSvyBalance;
            } else {
                return pending;
            }
        }
        return 0;
    }

    /// @notice unstake staked svy
    /// @param _amount the amount of svy to unstake
    /// Note Beware! you will loose all of your veSVY if you unstake any amount of svy!
    function unstake(
        uint256 _amount
    ) external override nonReentrant whenNotPaused {
        address sender = msg.sender;
        Checker.checkArgument(_amount > 0, "amount to unstake cannot be zero");
        Checker.checkArgument(
            users[sender].amount > _amount - 1,
            "not enough balance"
        );

        // reset last Release timestamp
        users[sender].lastRelease = block.timestamp;

        // update their balance before burning or sending back svy
        users[sender].amount -= _amount;

        // get user veSVY balance that must be burned
        uint256 userVeSvyBalance = balanceOf(sender);

        _burn(sender, userVeSvyBalance);
        _updateFactor(sender);

        // send back the staked svy
        svy.safeTransfer(sender, _amount);
        emit Unstaked(sender, _amount);
    }

    /// @notice get votes for veSVY
    /// @dev votes should only count if account has > threshold% of current cap reached
    /// @dev invVoteThreshold = (1/threshold%)*100
    /// @return the valid votes
    function getVotes(
        address _account
    ) external view virtual override returns (uint256) {
        uint256 veSvyBalance = balanceOf(_account);

        // check that user has more than voting treshold of maxCap and has svy in stake
        if (
            veSvyBalance * invVoteThreshold > users[_account].amount * maxCap &&
            isUser(_account)
        ) {
            return veSvyBalance;
        } else {
            return 0;
        }
    }

    /// @notice Update savvyPositionManager factor for a user.
    /// @param _addr The address of a user.
    function _updateFactor(address _addr) internal {
        if (address(savvyBooster) == address(0)) {
            return;
        }

        uint256 userVeSvyBal = balanceOf(_addr);
        uint256 totalVeSvyBal = totalSupply();
        savvyBooster.updatePendingRewardsWithVeSvy(
            _addr,
            userVeSvyBal,
            totalVeSvyBal
        );
    }

    /// @notice stake svy for user funded by the sender
    /// @dev the sender cannot unstake the SVY. Think of
    /// this as a transfer.
    /// @param _user the recipient of the staked SVY
    /// @param _amount the amount of SVY to stake
    function _stake(address _user, uint256 _amount) internal {
        Checker.checkArgument(_amount > 0, "amount to deposit cannot be zero");

        if (isUser(_user)) {
            // if user exists, first, claim their veSVY
            _claim(_user);
            // then, increment their holdings
            users[_user].amount += _amount;
        } else {
            // add new user to mapping
            users[_user].lastRelease = block.timestamp;
            users[_user].amount = _amount;
        }

        // Request Svy from user
        svy.safeTransferFrom(msg.sender, address(this), _amount);

        emit Staked(msg.sender, _user, _amount);
    }

    uint256[99] private __gap;
}

