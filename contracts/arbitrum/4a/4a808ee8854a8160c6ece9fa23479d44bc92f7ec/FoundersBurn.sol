// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";
import "./AddressUpgradeable.sol";
import "./SafeCastUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./IUniswapV2Router02.sol";
import "./IUniswapV2Pair.sol";

import "./IBattleflyAtlasStakerV02.sol";
import "./IFlywheelEmissions.sol";
import "./IGFly.sol";
import "./IBattleflyFounderVault.sol";
import "./ISpecialNFT.sol";
import "./IFoundersBurn.sol";

import "./console.sol";

//MMMMWKl.                                            .:0WMMMM//
//MMMWk,                                                .dNMMM//
//MMNd.                                                  .lXMM//
//MWd.    .','''....                         .........    .lXM//
//Wk.     ';......'''''.                ..............     .dW//
//K;     .;,         ..,'.            ..'..         ...     'O//
//d.     .;;.           .''.        ..'.            .'.      c//
//:       .','.           .''.    ..'..           ....       '//
//'         .';.            .''...'..           ....         .//
//.           ';.             .''..             ..           .//
//.            ';.                             ...           .//
//,            .,,.                           .'.            .//
//c             .;.                           '.             ;//
//k.            .;.             .             '.            .d//
//Nl.           .;.           .;;'            '.            :K//
//MK:           .;.          .,,',.           '.           'OW//
//MM0;          .,,..       .''  .,.       ...'.          'kWM//
//MMMK:.          ..'''.....'..   .'..........           ,OWMM//
//MMMMXo.             ..'...        ......             .cKMMMM//
//MMMMMWO:.                                          .,kNMMMMM//
//MMMMMMMNk:.                                      .,xXMMMMMMM//
//MMMMMMMMMNOl'.                                 .ckXMMMMMMMMM//

contract FoundersBurn is IFoundersBurn, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using AddressUpgradeable for address;
    using SafeCastUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    /// @dev The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    /// @dev The identifier of the role which allows accounts to run cron jobs.
    bytes32 public constant BATTLEFLY_BOT_ROLE = keccak256("BATTLEFLY_BOT");

    IERC20Upgradeable public MAGIC;
    IGFly public GFLY;
    IBattleflyAtlasStakerV02 public ATLAS_STAKER;
    IBattleflyFounderVault public FOUNDER_VAULT_V1;
    IBattleflyFounderVault public FOUNDER_VAULT_V2;
    IFlywheelEmissions public FLYWHEEL_EMISSIONS;
    ISpecialNFT public FOUNDERS_TOKEN;
    IUniswapV2Router02 public MAGIC_SWAP_ROUTER;
    IUniswapV2Pair public MAGIC_GFLY_LP;

    address public EXCEPTION_ADDRESS;
    address public DAO;

    bool public paused;
    uint256 public burnPositionIndex;
    uint256 public currentEpoch;
    uint256 public totalV1;
    uint256 public totalV2;
    uint256 public burntV1;
    uint256 public burntV2;
    uint256 public rewardsV1Claimed;
    uint256 public rewardsV2Claimed;
    uint256 public totalBackedV1AtStart;
    uint256 public totalBackedV2AtStart;
    uint256 public bpsDenominator;
    uint256 public slippageInBPS;

    mapping(address => bool) public pauseGuardians;
    mapping(uint256 => uint256) public buyBackAtEpoch;
    mapping(uint256 => uint256) public additionToBuyBackAmountAtEpoch;
    mapping(uint256 => uint256) public subtractionFromBuyBackAmountAtEpoch;
    mapping(uint256 => BurnPosition) public burnPositions;
    mapping(address => EnumerableSetUpgradeable.UintSet) private burnPositionsPerAccount;

    //UPGRADE FOR EXCEPTION BURN
    address public NO_REWARD_BURN_ADDRESS;
    uint256 public nonRewardBurntV1;
    uint256 public nonRewardBurntV2;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(ContractAddresses calldata contractAddresses) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        if (contractAddresses.magic == address(0)) revert InvalidAddress();
        if (contractAddresses.gFly == address(0)) revert InvalidAddress();
        if (contractAddresses.atlasStaker == address(0)) revert InvalidAddress();
        if (contractAddresses.founderVaultV1 == address(0)) revert InvalidAddress();
        if (contractAddresses.founderVaultV2 == address(0)) revert InvalidAddress();
        if (contractAddresses.flywheelEmissions == address(0)) revert InvalidAddress();
        if (contractAddresses.foundersToken == address(0)) revert InvalidAddress();
        if (contractAddresses.magicSwapRouter == address(0)) revert InvalidAddress();
        if (contractAddresses.magicGflyLp == address(0)) revert InvalidAddress();
        if (contractAddresses.exceptionAddress == address(0)) revert InvalidAddress();
        if (contractAddresses.dao == address(0)) revert InvalidAddress();
        if (contractAddresses.battleflyBot == address(0)) revert InvalidAddress();

        _setupRole(ADMIN_ROLE, contractAddresses.dao);
        _setupRole(ADMIN_ROLE, msg.sender); // This will be surrendered after deployment
        _setupRole(BATTLEFLY_BOT_ROLE, contractAddresses.battleflyBot);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BATTLEFLY_BOT_ROLE, ADMIN_ROLE);

        MAGIC = IERC20Upgradeable(contractAddresses.magic);
        GFLY = IGFly(contractAddresses.gFly);
        ATLAS_STAKER = IBattleflyAtlasStakerV02(contractAddresses.atlasStaker);
        FOUNDER_VAULT_V1 = IBattleflyFounderVault(contractAddresses.founderVaultV1);
        FOUNDER_VAULT_V2 = IBattleflyFounderVault(contractAddresses.founderVaultV2);
        FLYWHEEL_EMISSIONS = IFlywheelEmissions(contractAddresses.flywheelEmissions);
        FOUNDERS_TOKEN = ISpecialNFT(contractAddresses.foundersToken);
        MAGIC_SWAP_ROUTER = IUniswapV2Router02(contractAddresses.magicSwapRouter);
        MAGIC_GFLY_LP = IUniswapV2Pair(contractAddresses.magicGflyLp);
        EXCEPTION_ADDRESS = contractAddresses.exceptionAddress;
        DAO = contractAddresses.dao;

        totalV1 = 220;
        totalV2 = 2105;
        totalBackedV1AtStart = 340643440000000000000000;
        totalBackedV2AtStart = 3246168490000000000000000;
        bpsDenominator = 10000;
        slippageInBPS = 500;
        paused = true;
    }

    // ============================== Operations ==============================

    /**
     * @dev Burns founder tokens providing a list of token ids.
     */
    function burnTokens(uint256[] calldata tokenIds) external override notPaused nonReentrant {
        if (tokenIds.length > 0) {
            uint256 amountOFV1ToBurn;
            uint256 amountOFV2ToBurn;
            for (uint256 i = 0; i < tokenIds.length; i++) {
                if (FOUNDERS_TOKEN.ownerOf(tokenIds[i]) != msg.sender) revert InvalidOwner();
                if (FOUNDERS_TOKEN.getSpecialNFTType(tokenIds[i]) == 150) {
                    amountOFV1ToBurn += 1;
                    burntV1 += 1;
                } else {
                    amountOFV2ToBurn += 1;
                    burntV2 += 1;
                }
                FOUNDERS_TOKEN.transferFrom(
                    msg.sender,
                    address(0x000000000000000000000000000000000000dEaD),
                    tokenIds[i]
                );
            }
            uint256 toBurnV1 = (amountOFV1ToBurn * totalBackedV1AtStart) / totalV1;
            uint256 toBurnV2 = (amountOFV2ToBurn * totalBackedV2AtStart) / totalV2;
            uint256 baseAmount = ((toBurnV1 * 80) / 100) + ((toBurnV2 * 80) / 100);
            uint256 rewardsV1Amount = ((FOUNDER_VAULT_V1.pendingStakeBackAmount() - rewardsV1Claimed) *
                amountOFV1ToBurn) / (totalV1 + amountOFV1ToBurn - burntV1);
            uint256 rewardsV2Amount = ((FOUNDER_VAULT_V2.pendingStakeBackAmount() - rewardsV2Claimed) *
                amountOFV2ToBurn) / (totalV2 + amountOFV2ToBurn - burntV2);
            FLYWHEEL_EMISSIONS.adjustFoundersBaseAmounts(toBurnV1, toBurnV2);
            rewardsV1Claimed += rewardsV1Amount;
            rewardsV2Claimed += rewardsV2Amount;
            uint256 totalPayout = baseAmount + rewardsV1Amount + rewardsV2Amount;
            if (msg.sender == EXCEPTION_ADDRESS) {
                _createPosition(msg.sender, totalPayout, currentEpoch + 1, currentEpoch + 90, true);
            } else if(msg.sender != NO_REWARD_BURN_ADDRESS){
                _createPosition(msg.sender, totalPayout, currentEpoch + 1, currentEpoch + 90, false);
            } else {
                nonRewardBurntV1 += amountOFV1ToBurn;
                nonRewardBurntV2 += amountOFV2ToBurn;
            }
        }
    }

    function currentV1BackingInMagic() external view override returns (uint256) {
        uint256 toBurnV1 = totalBackedV1AtStart / totalV1;
        uint256 baseAmount = (toBurnV1 * 80) / 100;
        uint256 rewardsV1Amount = (FOUNDER_VAULT_V1.pendingStakeBackAmount() - rewardsV1Claimed) / (totalV1 - burntV1);
        uint256 backing = baseAmount + rewardsV1Amount;
        return backing;
    }

    function currentV2BackingInMagic() external view override returns (uint256) {
        uint256 toBurnV2 = totalBackedV2AtStart / totalV2;
        uint256 baseAmount = (toBurnV2 * 80) / 100;
        uint256 rewardsV2Amount = (FOUNDER_VAULT_V2.pendingStakeBackAmount() - rewardsV2Claimed) / (totalV2 - burntV2);
        uint256 backing = baseAmount + rewardsV2Amount;
        return backing;
    }

    /**
     * @dev CRON function to distribute burn payouts on a daily basis
     */
    function distributeBurnPayouts() external override notPaused onlyBattleflyBot {
        buyBackAtEpoch[currentEpoch + 1] =
            buyBackAtEpoch[currentEpoch] +
            additionToBuyBackAmountAtEpoch[currentEpoch + 1] -
            subtractionFromBuyBackAmountAtEpoch[currentEpoch];
        if (buyBackAtEpoch[currentEpoch + 1] > 0) {
            (uint256 reserveMagic, uint256 reserveGFly) = _getReserves();
            uint256 gFLYAmountToSell = MAGIC_SWAP_ROUTER.getAmountIn(
                buyBackAtEpoch[currentEpoch + 1],
                reserveGFly,
                reserveMagic
            );
            uint256 maxGFlyToSell = (gFLYAmountToSell * (bpsDenominator + slippageInBPS)) / bpsDenominator;
            GFLY.approve(address(MAGIC_SWAP_ROUTER), maxGFlyToSell);
            address[] memory routing = new address[](2);
            routing[0] = address(GFLY);
            routing[1] = address(MAGIC);
            MAGIC_SWAP_ROUTER.swapTokensForExactTokens(
                buyBackAtEpoch[currentEpoch + 1],
                maxGFlyToSell,
                routing,
                address(this),
                block.timestamp
            );
        }
        currentEpoch++;
        emit BurnPayoutsDistributed(currentEpoch);
    }

    /**
     * @dev Claimable founder burn payout for a position
     */
    function claimable(uint256 positionId) external view override returns (uint256) {
        return _claimable(positionId);
    }

    /**
     * @dev Claimable founder burn payout for an account
     */
    function claimableForAccount(address account) external view override returns (uint256) {
        uint256 toClaim;
        for (uint256 i = 0; i < burnPositionsPerAccount[account].length(); i++) {
            toClaim += _claimable(burnPositionsPerAccount[account].at(i));
        }
        return toClaim;
    }

    /**
     * @dev Claims pending burn payout for a position
     */
    function claim(uint256 positionId) external override notPaused nonReentrant {
        _claim(positionId);
    }

    /**
     * @dev Claims pending burn payout for an account
     */
    function claimAll() external override notPaused nonReentrant {
        uint256[] memory positionIds = burnPositionsPerAccount[msg.sender].values();
        for (uint256 i = 0; i < positionIds.length; i++) {
            _claim(positionIds[i]);
        }
    }

    /**
     * @dev Retrieves the burn positions per account
     */
    function burnPositionsOfAccount(address account) external view override returns (uint256[] memory) {
        return burnPositionsPerAccount[account].values();
    }


    /**
     * @dev Retrieves the total amount of treasury owned Magic from burns.
     */
    function treasuryOwnedMagicFromBurns() external view override returns (uint256) {
        uint256 exceptionAddressBurntAmount;
        uint256[] memory positionIds = burnPositionsPerAccount[EXCEPTION_ADDRESS].values();
        for(uint256 i = 0; i < positionIds.length; i++) {
            exceptionAddressBurntAmount += (burnPositions[positionIds[i]].amountPerEpoch) * 90;
        }
        uint256 toBurnV2 = totalBackedV2AtStart / totalV2;
        uint256 baseAmountV2 = (toBurnV2 * 80) / 100;
        uint256 toBurnV1 = totalBackedV1AtStart / totalV1;
        uint256 baseAmountV1 = (toBurnV1 * 80) / 100;
        return (baseAmountV2 * (burntV2 - nonRewardBurntV2)) + (baseAmountV1 * (burntV1 - nonRewardBurntV1)) - exceptionAddressBurntAmount;
    }

    /**
     * @dev Topup the contract with gFLY
     */
    function topupGFly(uint256 amount) external override {
        GFLY.transferFrom(msg.sender, address(this), amount);
    }

    /**
     * @dev Withdraw gFLY from the contract
     */
    function withdrawGFly(uint256 amount) external override onlyAdmin {
        GFLY.transfer(msg.sender, amount);
    }

    function _claimable(uint256 positionId) internal view returns (uint256) {
        uint256 endEpoch = burnPositions[positionId].end > currentEpoch ? currentEpoch : burnPositions[positionId].end;
        uint256 claimableEpochs = endEpoch - burnPositions[positionId].lastClaimedEpoch;
        return burnPositions[positionId].amountPerEpoch * claimableEpochs;
    }

    function _claim(uint256 positionId) internal {
        if (burnPositions[positionId].owner != msg.sender) revert InvalidOwner();
        uint256 toClaim = _claimable(positionId);
        burnPositions[positionId].lastClaimedEpoch = currentEpoch;
        if (msg.sender == EXCEPTION_ADDRESS) {
            ATLAS_STAKER.withdrawForFoundersBurn(toClaim);
        }
        MAGIC.transfer(burnPositions[positionId].owner, toClaim);
        if (burnPositions[positionId].end <= currentEpoch) {
            burnPositionsPerAccount[burnPositions[positionId].owner].remove(positionId);
            delete burnPositions[positionId];
        }
        emit PositionClaimed(msg.sender, positionId, toClaim);
    }

    function _createPosition(
        address account,
        uint256 payout,
        uint256 start,
        uint256 end,
        bool fromLiquidAmount
    ) internal {
        if (!fromLiquidAmount) {
            additionToBuyBackAmountAtEpoch[start] += payout / 90;
            subtractionFromBuyBackAmountAtEpoch[end] += payout / 90;
        }
        burnPositionIndex++;
        burnPositions[burnPositionIndex] = BurnPosition(account, payout / 90, start, end, currentEpoch);
        burnPositionsPerAccount[account].add(burnPositionIndex);
        emit BurnPositionCreated(account, burnPositionIndex, payout / 90, payout, start, end, fromLiquidAmount);
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function _sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert InvalidAddress();
    }

    // fetches and sorts the reserves for a pair
    function _getReserves() internal view returns (uint reserveMagic, uint reserveGFly) {
        (address token0, ) = _sortTokens(address(MAGIC), address(GFLY));
        (uint reserve0, uint reserve1, ) = MAGIC_GFLY_LP.getReserves();
        (reserveMagic, reserveGFly) = address(MAGIC) == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyPauseGuardian notPaused {
        paused = true;
        emit PauseStateChanged(true);
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyPauseGuardian {
        if (!paused) revert AlreadyUnPaused();
        paused = false;
        emit PauseStateChanged(false);
    }

    /**
    * @dev Sets the Non reward burn address
     */
    function setNonRewardBurnAddress(address nonRewardBurnAddress) external onlyAdmin {
        NO_REWARD_BURN_ADDRESS = nonRewardBurnAddress;
    }

    /**
     * @dev Sets the slippage in BPS
     */
    function setSlippageInBPS(uint256 slippageInBPS_) external onlyAdmin {
        slippageInBPS = slippageInBPS_;
    }

    /**
     * @dev Sets the state of a pause guardian
     */
    function setPauseGuardian(address account, bool state) external onlyAdmin {
        pauseGuardians[account] = state;
    }

    /**
     * @dev Gets the state of a pause guardian
     */
    function isPauseGuardian(address account) external view returns (bool) {
        return pauseGuardians[account];
    }

    // ============================== Modifiers ==============================

    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert AccessDenied();
        _;
    }

    modifier onlyBattleflyBot() {
        if (!hasRole(BATTLEFLY_BOT_ROLE, msg.sender)) revert AccessDenied();
        _;
    }

    modifier onlyPauseGuardian() {
        if (!pauseGuardians[msg.sender]) revert AccessDenied();
        _;
    }

    modifier notPaused() {
        if (paused) revert ContractPaused();
        _;
    }
}

