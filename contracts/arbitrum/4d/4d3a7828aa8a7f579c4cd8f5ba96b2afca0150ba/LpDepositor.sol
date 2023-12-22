pragma solidity 0.8.16;

import "./IBaseV1Voter.sol";
import "./IGauge.sol";
import "./IBribe.sol";
import "./IVotingEscrow.sol";

import "./IFeeDistributor.sol";
import "./IVeDepositor.sol";
import "./ILpDepositToken.sol";

import "./PausableUpgradeable.sol";
import "./AccessControlEnumerableUpgradeable.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

contract LpDepositor is
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint256 public constant PERCEISION = 1e18;

    // solidly contracts
    IERC20Upgradeable public SOLID;
    IVotingEscrow public votingEscrow;
    IBaseV1Voter public solidlyVoter;

    // monlith contracts
    IVeDepositor public moSolid;
    IFeeDistributor public feeDistributor;
    address public tokenWhitelister;
    address public depositTokenImplementation;
    address public splitter;

    uint256 public tokenID;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER_ROLE");
    bytes32 public constant SETTER_ROLE = keccak256("SETTER_ROLE");
    bytes32 public constant TREASURER_ROLE = keccak256("TREASURER_ROLE");

    struct Withdraw {
        uint256 amount; // amount to withdraw
        uint256 unlockTimestamp; // unlock timestamp
    }

    // pool -> gauge
    mapping(address => address) public gaugeForPool;
    // pool -> bribe
    mapping(address => address) public bribeForPool;
    // pool -> monolith deposit token
    mapping(address => address) public tokenForPool;
    // user -> pool -> deposit amount
    mapping(address => mapping(address => uint256)) public userBalances;
    // pool -> total deposit amount
    mapping(address => uint256) public totalBalances;
    // pool -> integrals (solid amount)
    mapping(address => uint256) public rewardIntegral;
    // user -> pool -> integrals (solid amount)
    mapping(address => mapping(address => uint256)) public rewardIntegralFor;
    // user -> pool -> claimable
    mapping(address => mapping(address => uint256)) public claimable;

    uint256 public rewardWithdrawDelay; // in seconds
    // user -> Withdraws
    mapping(address => Withdraw) public withdrawable;

    uint256 public stakersSolidShare; // precision is e18
    uint256 public stakersUnclaimedSolid;

    uint256 public platformSolidShare; // precision is e18
    uint256 public platformUnclaimedSolid;

    event RewardAdded(address indexed rewardsToken, uint256 reward);
    event Deposited(address indexed user, address indexed pool, uint256 amount);
    event Withdrawn(address indexed user, address indexed pool, uint256 amount);
    event RewardPaid(
        address indexed user,
        address indexed rewardsToken,
        uint256 reward
    );
    event WithdrawReward(
        address indexed user,
        address indexed rewardsToken,
        uint256 reward
    );
    event TransferDeposit(
        address indexed pool,
        address indexed from,
        address indexed to,
        uint256 amount
    );

    function initialize(
        IERC20Upgradeable _solid,
        IVotingEscrow _votingEscrow,
        IBaseV1Voter _solidlyVoter,
        uint256 _rewardWithdrawDelay,
        address admin,
        address pauser,
        address unpauser,
        address setter,
        address treasurer
    ) public initializer {
        __Pausable_init();
        __AccessControlEnumerable_init();

        SOLID = _solid;
        votingEscrow = _votingEscrow;
        solidlyVoter = _solidlyVoter;

        rewardWithdrawDelay = _rewardWithdrawDelay;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(UNPAUSER_ROLE, unpauser);
        _grantRole(SETTER_ROLE, setter);
        _grantRole(TREASURER_ROLE, treasurer);
    }

    function setAddresses(
        IVeDepositor _moSolid,
        address _monolithVoter,
        IFeeDistributor _feeDistributor,
        address _tokenWhitelister,
        address _depositToken,
        address _splitter
    ) external onlyRole(SETTER_ROLE) {
        moSolid = _moSolid;
        feeDistributor = _feeDistributor;
        tokenWhitelister = _tokenWhitelister;
        depositTokenImplementation = _depositToken;
        splitter = _splitter;

        SOLID.approve(address(_moSolid), type(uint256).max);
        _moSolid.approve(address(_feeDistributor), type(uint256).max);
        votingEscrow.setApprovalForAll(_monolithVoter, true);
        votingEscrow.setApprovalForAll(address(_moSolid), true);

        // for splitting and resetting votes
        votingEscrow.setApprovalForAll(_splitter, true);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(UNPAUSER_ROLE) {
        _unpause();
    }

    /**
     * @dev Ensure SOLID and moSolid are whitelisted
     */
    function whitelistProtocolTokens() external {
        require(tokenID != 0, "No initial NFT deposit");
        if (!solidlyVoter.isWhitelisted(address(SOLID))) {
            solidlyVoter.whitelist(address(SOLID), tokenID);
        }
        if (!solidlyVoter.isWhitelisted(address(moSolid))) {
            solidlyVoter.whitelist(address(moSolid), tokenID);
        }
    }

    /**
     * @notice Get pending SOLID rewards earned by `account`
     * @param account Account to query pending rewards for
     * @param pools List of pool addresses to query rewards for
     * @return pending Array of SOLID rewards for each item in `pool`
     */
    function pendingRewards(address account, address[] calldata pools)
        external
        view
        returns (uint256[] memory pending)
    {
        pending = new uint256[](pools.length);
        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];
            pending[i] = claimable[account][pool];
            uint256 balance = userBalances[account][pool];
            if (balance == 0) {
                continue;
            }

            uint256 integral = rewardIntegral[pool];
            uint256 total = totalBalances[pool];
            if (total > 0) {
                uint256 delta = IGauge(gaugeForPool[pool]).earned(
                    address(SOLID),
                    address(this)
                );
                delta -=
                    (delta * (stakersSolidShare + platformSolidShare)) /
                    PERCEISION;
                integral += (1e18 * delta) / total;
            }

            uint256 integralFor = rewardIntegralFor[account][pool];
            if (integralFor < integral) {
                pending[i] += (balance * (integral - integralFor)) / 1e18;
            }
        }
        return pending;
    }

    /**
     * @notice Deposit Solidly LP tokens into a gauge via this contract
     * @dev Each deposit is also represented via a new ERC20, the address
     * is available by querying `tokenForPool(pool)`
     * @param pool Address of the pool token to deposit
     * @param amount Quantity of tokens to deposit
     */
    function deposit(address pool, uint256 amount) external {
        require(tokenID != 0, "Must lock SOLID first");
        require(amount > 0, "Cannot deposit zero");

        address gauge = gaugeForPool[pool];
        uint256 total = totalBalances[pool];
        uint256 balance = userBalances[msg.sender][pool];

        if (gauge == address(0)) {
            gauge = solidlyVoter.gauges(pool);
            if (gauge == address(0)) {
                gauge = solidlyVoter.createGauge(pool);
            }
            gaugeForPool[pool] = gauge;
            bribeForPool[pool] = solidlyVoter.bribes(gauge);
            tokenForPool[pool] = _deployDepositToken(pool);
            IERC20Upgradeable(pool).approve(gauge, type(uint256).max);
        } else {
            _updateIntegrals(msg.sender, pool, gauge, balance, total);
        }

        IERC20Upgradeable(pool).transferFrom(msg.sender, address(this), amount);
        IGauge(gauge).deposit(amount, tokenID);

        userBalances[msg.sender][pool] = balance + amount;
        totalBalances[pool] = total + amount;
        IDepositToken(tokenForPool[pool]).mint(msg.sender, amount);
        emit Deposited(msg.sender, pool, amount);
    }

    /**
     * @notice Withdraw Solidly LP tokens
     * @param pool Address of the pool token to withdraw
     * @param amount Quantity of tokens to withdraw
     */
    function withdraw(address pool, uint256 amount) external {
        address gauge = gaugeForPool[pool];
        uint256 total = totalBalances[pool];
        uint256 balance = userBalances[msg.sender][pool];

        require(gauge != address(0), "Unknown pool");
        require(amount > 0, "Cannot withdraw zero");
        require(balance >= amount, "Insufficient deposit");

        _updateIntegrals(msg.sender, pool, gauge, balance, total);

        userBalances[msg.sender][pool] = balance - amount;
        totalBalances[pool] = total - amount;

        IDepositToken(tokenForPool[pool]).burn(msg.sender, amount);
        IGauge(gauge).withdraw(amount);
        IERC20Upgradeable(pool).transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, pool, amount);
    }

    /**
     * @notice Claim SOLID rewards earned from depositing LP tokens
     * @param pools List of pools to claim for
     */
    function getReward(address[] calldata pools) external {
        uint256 claims;
        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];
            address gauge = gaugeForPool[pool];
            uint256 total = totalBalances[pool];
            uint256 balance = userBalances[msg.sender][pool];

            _updateIntegrals(msg.sender, pool, gauge, balance, total);
            claims += claimable[msg.sender][pool];
            delete claimable[msg.sender][pool];
        }
        if (claims > 0) {
            withdrawable[msg.sender].amount += claims;
            withdrawable[msg.sender].unlockTimestamp =
                block.timestamp +
                rewardWithdrawDelay;
            emit RewardPaid(msg.sender, address(SOLID), claims);
        }
    }

    function withdrawReward() external {
        require(
            block.timestamp > withdrawable[msg.sender].unlockTimestamp,
            "Withdraw is still locked"
        );

        uint256 amount = withdrawable[msg.sender].amount;
        if (amount > 0) {
            SOLID.transfer(msg.sender, amount);
            withdrawable[msg.sender].amount = 0;
            emit WithdrawReward(msg.sender, address(SOLID), amount);
        }
    }

    function setRewardWithdrawDelay(uint256 _rewardWithdrawDelay)
        external
        onlyRole(SETTER_ROLE)
    {
        rewardWithdrawDelay = _rewardWithdrawDelay;
    }

    /**
     * @notice Claim incentive tokens from gauge and/or bribe contracts
     * and transfer them to `FeeDistributor`
     * @dev This method is unguarded, anyone can claim any reward at any time.
     * Claimed tokens are streamed to moSolid stakers starting at the beginning
     * of the following epoch week.
     * @param pool Address of the pool token to claim for
     * @param gaugeRewards List of incentive tokens to claim for in the pool's gauge
     * @param bribeRewards List of incentive tokens to claim for in the pool's bribe contract
     */
    function claimLockerRewards(
        address pool,
        address[] calldata gaugeRewards,
        address[] calldata bribeRewards
    ) external {
        // claim pending gauge rewards for this pool to update `stakersUnclaimedSolid`
        address gauge = gaugeForPool[pool];
        require(gauge != address(0), "Unknown pool");
        _updateIntegrals(address(0), pool, gauge, 0, totalBalances[pool]);

        address distributor = address(feeDistributor);
        uint256 amount;

        // fetch gauge rewards and push to the fee distributor
        if (gaugeRewards.length > 0) {
            IGauge(gauge).getReward(address(this), gaugeRewards);
            for (uint256 i = 0; i < gaugeRewards.length; i++) {
                IERC20Upgradeable reward = IERC20Upgradeable(gaugeRewards[i]);
                require(reward != SOLID, "!SOLID as gauge reward");
                amount = IERC20Upgradeable(reward).balanceOf(address(this));
                if (amount == 0) {
                    continue;
                }
                if (reward.allowance(address(this), distributor) == 0) {
                    reward.safeApprove(distributor, type(uint256).max);
                }
                IFeeDistributor(distributor).depositFee(
                    address(reward),
                    amount
                );
            }
        }

        // fetch bribe rewards and push to the fee distributor
        if (bribeRewards.length > 0) {
            uint256 solidBalance = SOLID.balanceOf(address(this));
            IBribe(bribeForPool[pool]).getReward(tokenID, bribeRewards);
            for (uint256 i = 0; i < bribeRewards.length; i++) {
                IERC20Upgradeable reward = IERC20Upgradeable(bribeRewards[i]);
                if (reward == SOLID) {
                    // when SOLID is received as a bribe, add it to the balance
                    // that will be converted to moSolid prior to distribution
                    uint256 newBalance = SOLID.balanceOf(address(this));
                    uint256 delta = newBalance - solidBalance;

                    stakersUnclaimedSolid +=
                        (delta * stakersSolidShare) /
                        (stakersSolidShare + platformSolidShare);

                    platformUnclaimedSolid +=
                        (delta * platformSolidShare) /
                        (stakersSolidShare + platformSolidShare);

                    solidBalance = newBalance;
                    continue;
                }
                amount = reward.balanceOf(address(this));
                if (amount == 0) {
                    continue;
                }
                if (reward.allowance(address(this), distributor) == 0) {
                    reward.safeApprove(distributor, type(uint256).max);
                }
                IFeeDistributor(distributor).depositFee(
                    address(reward),
                    amount
                );
            }
        }

        if (stakersUnclaimedSolid > 0) {
            IFeeDistributor(distributor).depositFee(
                address(SOLID),
                stakersUnclaimedSolid
            );
            stakersUnclaimedSolid = 0;
        }
    }

    function claimPlatformFee(address to) external onlyRole(TREASURER_ROLE) {
        SOLID.safeTransfer(to, platformUnclaimedSolid);
        platformUnclaimedSolid = 0;
    }

    function setFees(uint256 _stakersSolidShare, uint256 _platformSolidShare)
        external
        onlyRole(SETTER_ROLE)
    {
        require(
            _stakersSolidShare + _platformSolidShare <= PERCEISION,
            "Shares are too high"
        );
        stakersSolidShare = _stakersSolidShare;
        platformSolidShare = _platformSolidShare;
    }

    // External guarded functions - only callable by other protocol contracts ** //

    function transferDeposit(
        address pool,
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        require(msg.sender == tokenForPool[pool], "Unauthorized caller");
        require(amount > 0, "Cannot transfer zero");

        address gauge = gaugeForPool[pool];
        uint256 total = totalBalances[pool];

        uint256 balance = userBalances[from][pool];
        require(balance >= amount, "Insufficient balance");
        _updateIntegrals(from, pool, gauge, balance, total);
        userBalances[from][pool] = balance - amount;

        balance = userBalances[to][pool];
        _updateIntegrals(to, pool, gauge, balance, total - amount);
        userBalances[to][pool] = balance + amount;
        emit TransferDeposit(pool, from, to, amount);
        return true;
    }

    function whitelist(address token) external returns (bool) {
        require(msg.sender == tokenWhitelister, "Only whitelister");
        require(
            votingEscrow.balanceOfNFT(tokenID) > solidlyVoter.listing_fee(),
            "Not enough veSOLID"
        );
        solidlyVoter.whitelist(token, tokenID);
        return true;
    }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenID,
        bytes calldata
    ) external returns (bytes4) {
        // VeDepositor transfers the NFT to this contract so this callback is required
        require(_operator == address(moSolid));

        if (tokenID == 0) {
            tokenID = _tokenID;
        }

        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    function detachGauges(address[] memory gaugeAddresses) external {
        require(msg.sender == splitter, "Not Splitter");

        uint256 amount;
        for (uint256 i = 0; i < gaugeAddresses.length; i++) {
            // max withdraw is 1e16 token to avoid large asset transfer
            amount = IGauge(gaugeAddresses[i]).balanceOf(address(this));
            if (amount > 0) {
                if (amount > 1e16) amount = 1e16;
                IGauge(gaugeAddresses[i]).withdrawToken(amount, tokenID);
                IGauge(gaugeAddresses[i]).deposit(amount, 0);
            }
        }
    }

    function reattachGauges(address[] memory gaugeAddresses) external {
        require(msg.sender == splitter, "Not Splitter");

        uint256 amount = 1e16;
        for (uint256 i = 0; i < gaugeAddresses.length; i++) {
            amount = IGauge(gaugeAddresses[i]).balanceOf(address(this));
            if (amount > 0) {
                if (amount > 1e16) amount = 1e16;
                IGauge(gaugeAddresses[i]).withdrawToken(amount, 0);
                IGauge(gaugeAddresses[i]).deposit(amount, tokenID);
            }
        }
    }

    // ** Internal functions ** //

    function _deployDepositToken(address pool)
        internal
        returns (address token)
    {
        // taken from https://solidity-by-example.org/app/minimal-proxy/
        bytes20 targetBytes = bytes20(depositTokenImplementation);
        assembly {
            let clone := mload(0x40)
            mstore(
                clone,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone, 0x14), targetBytes)
            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            token := create(0, clone, 0x37)
        }
        IDepositToken(token).initialize(pool);
        return token;
    }

    function _updateIntegrals(
        address user,
        address pool,
        address gauge,
        uint256 balance,
        uint256 total
    ) internal whenNotPaused {
        uint256 integral = rewardIntegral[pool];
        if (total > 0) {
            uint256 delta = SOLID.balanceOf(address(this));
            address[] memory rewards = new address[](1);
            rewards[0] = address(SOLID);
            IGauge(gauge).getReward(address(this), rewards);
            delta = SOLID.balanceOf(address(this)) - delta;
            if (delta > 0) {
                uint256 stakersFee = (delta * stakersSolidShare) / PERCEISION;
                stakersUnclaimedSolid += stakersFee;

                uint256 platformFee = (delta * platformSolidShare) / PERCEISION;
                platformUnclaimedSolid += platformFee;

                delta -= stakersFee + platformFee;

                integral += (1e18 * delta) / total;
                rewardIntegral[pool] = integral;
            }
        }
        if (user != address(0)) {
            uint256 integralFor = rewardIntegralFor[user][pool];
            if (integralFor < integral) {
                claimable[user][pool] +=
                    (balance * (integral - integralFor)) /
                    1e18;
                rewardIntegralFor[user][pool] = integral;
            }
        }
    }
}

