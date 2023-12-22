// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import { IGauge } from "./IGAUGE.sol";
import { IPool } from "./IPOOL.sol";

import { ERC20 } from "./ERC20.sol";
import { WETH } from "./WETH.sol";
import { SafeTransferLib } from "./SafeTransferLib.sol";
import { FixedPointMathLib } from "./FixedPointMathLib.sol";

/**
 * Bond design:
 * 0) Arbitrum deployment
 * 1) ERC4626 guidance
 * 2) Accept [USDC, USDT, Curve2CoinStablePoolToken(USDC/USDT)] tokens for deposits for ease of investment
 * 3) Treasurey Tokens are USDC / USDT (low risk)
 * 4) Rewards are fixed at 10% per year pro-rata
 * 5) Minimum lock-up period of investment (6 months)
 * 6) All balances are in terms of Curve 2Pool (USDC/USDT) LP value, which mitigates dpeg attacks
 */

/// @title GreenBond vault contract to provide liquidity and earn rewards
/// @author @sandybradley
/// @notice ERC4626 with some key differences:
/// 0) Accept [USDC, USDT, Curve2CoinStablePoolToken(USDC/USDT)] tokens for deposits
contract GreenBond is ERC20("GreenBond", "gBOND", 18) {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                               ERRORS
    //////////////////////////////////////////////////////////////*/

    error InsufficientAsset();
    error InsufficientLiquidity();
    error InsufficientBalance();
    error InsufficientAllowance();
    error UnknownToken();
    error ZeroShares();
    error ZeroAmount();
    error ZeroAddress();
    error Overflow();
    error IdenticalAddresses();
    error InsufficientLockupTime();
    error Unauthorized();
    error NoRewardsToClaim();
    error NotProject();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    

    uint8 public constant USDC_INDEX = 0;
    uint8 public constant USDT_INDEX = 1;
    /// @notice USDC address
    address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    /// @notice USDT address
    address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    /// @notice Curve 2 Pool (USDT / USDC)
    address public constant STABLE_POOL = 0x7f90122BF0700F9E7e1F688fe926940E8839F353;
    /// @notice Curve Gauge for 2 Pool (USDT / USDC)
    address public constant GAUGE = 0xCE5F24B7A95e9cBa7df4B54E911B4A3Dc8CDAf6f;
    uint256 public constant YEAR_IN_SECONDS = 365 days;
    ERC20 public constant asset = ERC20(STABLE_POOL);
    
    /*//////////////////////////////////////////////////////////////
                               GLOBALS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fixed reward percent per year
    uint16 public FIXED_INTEREST = 10;

    /// @notice Deposit lockup time, default 3 months
    uint64 public LOCKUP = 3 * 30 days;

    /// @notice Governance address
    address public GOV;

    /// @notice Transient tokens deployed to project (~ 3 months lock-up)
    uint256 public DEPLOYED_TOKENS;

    /// @notice Time weighted average lockup time
    mapping(address => uint256) public depositTimestamps;

    mapping(address => uint256) private rewards;

    mapping(address => uint256) private lastClaimTimestamps;

    /*//////////////////////////////////////////////////////////////
                                PROJECTS
    //////////////////////////////////////////////////////////////*/

    struct Project {
        bool isActive;
        bool isCompleted;
        address admin;
        uint128 totalAssetsSupplied;
        uint128 totalAssetsRepaid;
        string projectName;
        string masterAgreement;
    }

    uint256 public projectCount;
    mapping(uint256 => Project) public projects;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit event
    event Deposit(address indexed depositor, address token, uint256 amount, uint256 shares);

    /// @notice Withdraw event
    event Withdraw(address indexed receiver, address token, uint256 amount, uint256 shares);

    event Claim(address indexed receiver, address token, uint256 amount, uint256 shares);
    event Compound(address indexed receiver, uint256 shares);
    event PaidProject(address admin, uint256 amount, uint256 projectId);
    event ReceivedIncome(address indexed sender, uint256 assets, uint256 projectId);
    event RewardsClaimed(address indexed sender, address token, uint256 tokenAmount, uint256 shares);
    event RewardsCompounded(address indexed sender, uint256 shares);
    event ProjectRegistered(uint256 indexed project);

    /*//////////////////////////////////////////////////////////////
                                 CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() {
        GOV = tx.origin; // CREATE2 deployment requires tx.origin
    }

    /*//////////////////////////////////////////////////////////////
                                 GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    function _govCheck() internal view {
        if (msg.sender != GOV) revert Unauthorized();
    }

    function changeLockup(uint64 newLockup) external {
        _govCheck();
        LOCKUP = newLockup;
    }

    function changeGov(address newGov) external {
        _govCheck();
        GOV = newGov;
    }

    function changeInterest(uint16 newInterest) external {
        _govCheck();
        FIXED_INTEREST = newInterest;
    }

    function _tokenCheck(address token) internal pure {
        if (token != USDC && token != USDT && token != STABLE_POOL) revert UnknownToken();
    }

    function _liquidityCheck(uint256 assets) internal view {
        if (_isZero(assets)) revert ZeroAmount();
        if (IGauge(GAUGE).balanceOf(address(this)) < assets) revert InsufficientLiquidity();
    }

    /**
     * @dev Registers a new Project
     */
    function registerProject(address projectAdmin, string calldata projectName) external returns (uint256) {
        _govCheck();
        if (projectAdmin == address(0)) revert ZeroAddress();

        Project memory project;
        project.admin = projectAdmin;
        project.projectName = projectName;

        unchecked{
            ++projectCount;
        }

        projects[projectCount] = project;

        emit ProjectRegistered(projectCount);

        return projectCount;
    }

    function linkProjectAgreement(uint256 projectId, string calldata masterAgreement) external {
        _govCheck();
        projects[projectId].masterAgreement = masterAgreement;
    }

    function completeProject(uint256 projectId) external {
        _govCheck();
        if (projects[projectId].totalAssetsRepaid > projects[projectId].totalAssetsSupplied) {
            projects[projectId].isCompleted = true;
        }
    }

    function payProject(address token, uint256 tokenAmount, uint256 projectId) external {
        _govCheck();
        if (projectId > projectCount) revert NotProject();
        _tokenCheck(token);
        if (!projects[projectId].isActive) {
            projects[projectId].isActive = true;
        }
        uint256[2] memory amounts;
        if (token == USDT) amounts[USDT_INDEX] = tokenAmount;
        else amounts[USDC_INDEX] = tokenAmount;
        uint256 assets = IPool(STABLE_POOL).calc_token_amount(amounts, false) * 998/1000;
        projects[projectId].totalAssetsSupplied += uint128(assets);

        tokenAmount = _beforeWithdraw(token, assets);

        unchecked {
            DEPLOYED_TOKENS += assets;
        }

        ERC20(token).approve(projects[projectId].admin, tokenAmount);

        emit PaidProject(projects[projectId].admin, assets, projectId);

        ERC20(token).safeTransfer(projects[projectId].admin, tokenAmount);
    }

    function receiveIncome(address token, uint256 tokenAmount, uint256 projectId) external {
        _tokenCheck(token);
        uint256 assets = _deposit(token, tokenAmount);
        projects[projectId].totalAssetsRepaid += uint128(assets);
        if (assets > DEPLOYED_TOKENS) {
            delete DEPLOYED_TOKENS;
        } else {
            unchecked {
                DEPLOYED_TOKENS -= assets;
            }
        }
        emit ReceivedIncome(msg.sender, assets, projectId);
    }

    function recoverToken(address token, address receiver, uint256 tokenAmount) external {
        _govCheck();
        ERC20(token).safeTransfer(receiver, tokenAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposit token for gBOND
    /// @dev Requires token approval or value sent with call
    /// @param token Address of token being deposited (For eth sent use weth address)
    /// @param tokenAmount Amount of token to deposit
    /// @return shares returned to sender for deposit
    function deposit(address token, uint256 tokenAmount) external payable virtual returns (uint256 shares) {
        uint256 assets = _deposit(token, tokenAmount);
        shares = previewDeposit(assets);
        if (_isZero(shares)) revert ZeroShares();

        // Set the deposit timestamp for the user
        _updateDepositTimestamp(msg.sender, shares);

        _mint(msg.sender, shares);

        emit Deposit(msg.sender, token, tokenAmount, shares);
    }

    function _updateDepositTimestamp(address account, uint256 shares) internal {
        // Set the deposit timestamp for the user
        uint256 prevBalance = balanceOf[account];
        if (_isZero(prevBalance)) {
            depositTimestamps[account] = block.timestamp;
        } else {
            // multiple deposits, so weight timestamp by amounts
            unchecked {
                depositTimestamps[account] = ((depositTimestamps[account] * prevBalance) + (block.timestamp * shares)) / (prevBalance + shares);
            }
        }
    }

    /// @notice Withdraw shares for usdt. Requires sender to have approved vault to spend share amount
    /// @param token Either Usdt or Usdc
    /// @param shares Shares to withdraw
    /// @return tokenAmount amount of tokens returned
    function withdraw(address token, uint256 shares) public virtual returns (uint256 tokenAmount) {
        _tokenCheck(token);
        if (block.timestamp < depositTimestamps[msg.sender] + LOCKUP) revert InsufficientLockupTime();

        // compound rewards, add to shares
        shares += _compound();
        if (shares > balanceOf[msg.sender]) revert InsufficientBalance();

        uint256 assets = previewRedeem(shares);
        _liquidityCheck(assets);

        tokenAmount = _beforeWithdraw(token, assets);

        _burn(msg.sender, shares);

        emit Withdraw(msg.sender, token, tokenAmount, shares);

        ERC20(token).safeTransfer(msg.sender, tokenAmount);
    }

    function claimRewards(address token) external returns (uint256 tokenAmount) {
        _tokenCheck(token);
        uint256 unclaimedRewards = _calculateUnclaimedRewards(msg.sender);
        if (_isZero(unclaimedRewards)) revert NoRewardsToClaim();
        uint256 assets = previewRedeem(unclaimedRewards);
        _liquidityCheck(assets);

        unchecked {
            rewards[msg.sender] += unclaimedRewards;
            lastClaimTimestamps[msg.sender] = block.timestamp;
        }

        tokenAmount = _beforeWithdraw(token, assets);
        ERC20(token).safeTransfer(msg.sender, tokenAmount);

        emit RewardsClaimed(msg.sender, token, tokenAmount, unclaimedRewards);
    }

    function _compound() internal returns (uint256 unclaimedRewards) {
        unclaimedRewards = _calculateUnclaimedRewards(msg.sender);
        if (_isZero(unclaimedRewards)) return unclaimedRewards;

        unchecked {
            rewards[msg.sender] += unclaimedRewards;
            lastClaimTimestamps[msg.sender] = block.timestamp;
        }

        _mint(msg.sender, unclaimedRewards);

        emit RewardsCompounded(msg.sender, unclaimedRewards);
    }

    function _calculateUnclaimedRewards(address user) internal view returns (uint256 unclaimedRewards) {
        uint256 lastClaimTimestamp = lastClaimTimestamps[user];
        if (_isZero(lastClaimTimestamp)) {
            // User has never claimed rewards before, so calculate from deposit timestamp
            lastClaimTimestamp = depositTimestamps[user];
        }
        unchecked {
            uint256 elapsedTime = block.timestamp - lastClaimTimestamp;
            unclaimedRewards = uint256(FIXED_INTEREST) * elapsedTime * balanceOf[user] / (100 * YEAR_IN_SECONDS);
        }
        return unclaimedRewards;
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function totalAssets() public view virtual returns (uint256) {
        unchecked {
            return (DEPLOYED_TOKENS + IGauge(GAUGE).balanceOf(address(this)));
        }
    }

    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

    /*//////////////////////////////////////////////////////////////
                     DEPOSIT/WITHDRAWAL LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function maxDeposit(address) public view virtual returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(address owner) public view virtual returns (uint256) {
        return convertToAssets(balanceOf[owner]);
    }

    function maxRedeem(address owner) public view virtual returns (uint256) {
        return balanceOf[owner];
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL HOOKS LOGIC
    //////////////////////////////////////////////////////////////*/

    function _beforeWithdraw(address token, uint256 assets) internal virtual returns (uint256) {
        // withdraw from Curve Gauge
        IGauge(GAUGE).withdraw(assets, address(this), true);
        if (token == STABLE_POOL) return assets;
        // withdraw from Curve pool
        int128 index;
        if (token == USDT) index = 1;
        uint256 minTokenAmount = IPool(STABLE_POOL).calc_withdraw_one_coin(assets, index) * 98 / 100;
        return IPool(STABLE_POOL).remove_liquidity_one_coin(assets, index, minTokenAmount);
    }

    /// @notice Adds liquidity to an currve 2 pool from USDT / USDC
    /// @param token token to stake
    /// @param tokenAmount amount to stake
    /// @return assets amount of liquidity token received, sent to msg.sender
    function _stakeLiquidity(address token, uint256 tokenAmount) internal returns (uint256 assets) {
        if (tokenAmount < 2000) revert InsufficientAsset();
        uint256[2] memory amounts;
        if (token == USDT) amounts[USDT_INDEX] = tokenAmount;
        else amounts[USDC_INDEX] = tokenAmount;
        uint256 minMintAmount = IPool(STABLE_POOL).calc_token_amount(amounts, true) * 98 / 100;
        ERC20(token).approve(STABLE_POOL, tokenAmount);
        assets = IPool(STABLE_POOL).add_liquidity(amounts, minMintAmount);
    }

    /// @custom:gas Uint256 zero check gas saver
    /// @notice Uint256 zero check gas saver
    /// @param value Number to check
    function _isZero(uint256 value) internal pure returns (bool boolValue) {
        /// @solidity memory-safe-assembly
        assembly {
            boolValue := iszero(value)
        }
    }

    /// @custom:gas Uint256 not zero check gas saver
    /// @notice Uint256 not zero check gas saver
    /// @param value Number to check
    function _isNonZero(uint256 value) internal pure returns (bool boolValue) {
        /// @solidity memory-safe-assembly
        assembly {
            boolValue := iszero(iszero(value))
        }
    }

    /// @notice Function to receive Ether. msg.data must be empty
    receive() external payable virtual { }

    /// @notice Fallback function is called when msg.data is not empty
    fallback() external payable { }

    function _deposit(address token, uint256 tokenAmount) internal returns (uint256 assets) {
        if (ERC20(token).allowance(msg.sender, address(this)) < tokenAmount) revert InsufficientAllowance();
        if (token == USDC || token == USDT) {
            // Need to transfer before minting or ERC777s could reenter.
            ERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);
            assets = _stakeLiquidity(token, tokenAmount);
        } else if (token == STABLE_POOL) {
            // Need to transfer before minting or ERC777s could reenter.
            ERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);
            assets = tokenAmount;
        } else {
            revert UnknownToken();
        }
        // deposit LP to curve
        asset.approve(GAUGE, assets);
        IGauge(GAUGE).deposit(assets);
    }

    /// @dev override erc20 transfer to update receiver deposit timestamp
    function transfer(address to, uint256 amount) public override returns (bool) {
        balanceOf[msg.sender] -= amount;

        _updateDepositTimestamp(to, amount);

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    /// @dev override erc20 transferFrom to update receiver deposit timestamp
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;

        balanceOf[from] -= amount;

        _updateDepositTimestamp(to, amount);

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }
}

