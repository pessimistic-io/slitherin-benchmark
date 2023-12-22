// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";
import "./AddressUpgradeable.sol";
import "./SafeCastUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./AccessControlUpgradeable.sol";
import "./MerkleProofUpgradeable.sol";

import "./IBattleflyAtlasStakerV02.sol";
import "./IBattleflyTreasuryFlywheelVault.sol";
import "./IFlywheelEmissions.sol";
import "./IGFly.sol";

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

contract FlywheelEmissions is IFlywheelEmissions, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using AddressUpgradeable for address;
    using SafeCastUpgradeable for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /// @dev The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    /// @dev The identifier of the role which allows accounts to run cron jobs.
    bytes32 public constant BATTLEFLY_BOT_ROLE = keccak256("BATTLEFLY_BOT");

    uint256 public emissionsEpoch;
    bytes32 public merkleRoot;

    IERC20Upgradeable public MAGIC;
    IGFly public GFLY;
    IBattleflyAtlasStakerV02 public ATLAS_STAKER;
    IBattleflyTreasuryFlywheelVault public TREASURY_VAULT;

    address public GFLY_STAKING;
    address public GFLY_MAGICSWAP;
    address public OPEX;
    address public VAULT1;
    address public VAULT2;
    address public CHEESE;
    address public DIGI;
    address public DAO;

    mapping(uint64 => HarvesterEmission) public harvesterEmissionsForEpoch;
    mapping(uint64 => uint256) public flywheelEmissionsForEpoch;
    mapping(address => uint256) public currentVaultHarvesterStake;
    mapping(address => mapping(uint64 => uint256)) public vaultHarvesterStakeAtEpoch;
    mapping(uint64 => uint256) public rewardsActivatedInBPSAtEpoch;
    mapping(address => uint256) public claimed;
    mapping(address => address) public vaultAddressToGFlyGameAddress;

    // UPGRADE TO ADD EXTRA LOCKED TREASURY WALLETS

    address public TREASURY2;
    address public TREASURY3;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(ContractAddresses calldata contractAddresses) external initializer {
        __AccessControl_init();
        __ReentrancyGuard_init();

        require(contractAddresses.magic != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        require(contractAddresses.gFly != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        require(contractAddresses.gFlyStaking != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        require(contractAddresses.atlasStaker != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        require(contractAddresses.treasuryVault != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        require(contractAddresses.opex != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        require(contractAddresses.vault1 != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        require(contractAddresses.vault2 != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        require(contractAddresses.cheese != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        require(contractAddresses.digi != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        require(contractAddresses.battleflyBot != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        require(contractAddresses.dao != address(0), "FlywheelEmissions:INVALID_ADDRESS");

        _setupRole(ADMIN_ROLE, contractAddresses.dao);
        _setupRole(ADMIN_ROLE, msg.sender); // This will be surrendered after deployment
        _setupRole(BATTLEFLY_BOT_ROLE, contractAddresses.battleflyBot);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(BATTLEFLY_BOT_ROLE, ADMIN_ROLE);

        MAGIC = IERC20Upgradeable(contractAddresses.magic);
        GFLY = IGFly(contractAddresses.gFly);
        GFLY_STAKING = contractAddresses.gFlyStaking;
        ATLAS_STAKER = IBattleflyAtlasStakerV02(contractAddresses.atlasStaker);
        TREASURY_VAULT = IBattleflyTreasuryFlywheelVault(contractAddresses.treasuryVault);
        DAO = contractAddresses.dao;
        OPEX = contractAddresses.opex;
        VAULT1 = contractAddresses.vault1;
        VAULT2 = contractAddresses.vault2;
        CHEESE = contractAddresses.cheese;
        DIGI = contractAddresses.digi;
    }

    // ============================== Operations ==============================

    function setGFlyGameAddress(address vault, address gFlyGameAddress) external override onlyAdmin {
        vaultAddressToGFlyGameAddress[vault] = gFlyGameAddress;
        emit GFlyGameAddressSet(vault, gFlyGameAddress);
    }

    /**
     * @dev Topup harvester emissions
     */
    function topupHarvesterEmissions(
        uint256 amount,
        uint256 harvesterMagic,
        uint256 additionalFlywheelMagic
    ) external override onlyAdmin {
        require(amount > 0, "FlywheelEmissions:CANNOT_DEPOSIT_0");
        uint64 epoch = ATLAS_STAKER.currentEpoch();
        require(epoch >= ATLAS_STAKER.transitionEpoch(), "FlywheelEmissions:TOPUP_ON_V1");
        MAGIC.safeTransferFrom(msg.sender, address(this), amount);
        harvesterEmissionsForEpoch[epoch].amount += amount;
        harvesterEmissionsForEpoch[epoch].harvesterMagic = harvesterMagic;
        harvesterEmissionsForEpoch[epoch].additionalFlywheelMagic = additionalFlywheelMagic;
        uint256 v1VaultHarvesterStake = currentVaultHarvesterStake[VAULT1];
        uint256 v2VaultHarvesterStake = currentVaultHarvesterStake[VAULT2];
        uint256 cheeseHarvesterStake = currentVaultHarvesterStake[CHEESE];
        uint256 digiHarvesterStake = currentVaultHarvesterStake[DIGI];
        vaultHarvesterStakeAtEpoch[VAULT1][epoch] = v1VaultHarvesterStake;
        vaultHarvesterStakeAtEpoch[VAULT2][epoch] = v2VaultHarvesterStake;
        vaultHarvesterStakeAtEpoch[CHEESE][epoch] = cheeseHarvesterStake;
        vaultHarvesterStakeAtEpoch[DIGI][epoch] = digiHarvesterStake;
        uint256 activatedRewardsInBPS = getActivatedRewardsInBPS();
        rewardsActivatedInBPSAtEpoch[epoch] = activatedRewardsInBPS;
        emit HarvesterEmissionsToppedUp(
            amount,
            harvesterMagic,
            additionalFlywheelMagic,
            v1VaultHarvesterStake,
            v2VaultHarvesterStake,
            cheeseHarvesterStake,
            digiHarvesterStake,
            epoch,
            activatedRewardsInBPS
        );
    }

    /**
     * @dev Topup the flywheel emissions
     */
    function topupFlywheelEmissions(uint256 amount) external override {
        require(msg.sender == address(ATLAS_STAKER), "FlywheelEmissions:ACCESS_DENIED");
        uint64 epoch = ATLAS_STAKER.currentEpoch();
        require(epoch >= ATLAS_STAKER.transitionEpoch(), "FlywheelEmissions:TOPUP_ON_V1");
        if (amount > 0) {
            flywheelEmissionsForEpoch[epoch] += amount;
            MAGIC.safeTransferFrom(msg.sender, address(this), amount);
            emit FlywheelEmissionsToppedUp(epoch, amount);
        }
    }

    /**
     * @dev Set MAGIC harvester amounts for participating vaults
     */
    function setVaultHarvesterStake(uint256 _amount, address _vault) external override onlyAdmin {
        require(ATLAS_STAKER.currentEpoch() >= ATLAS_STAKER.transitionEpoch(), "FlywheelEmissions:SET_ON_V1");
        require(
            _vault == VAULT1 || _vault == VAULT2 || _vault == CHEESE || _vault == DIGI,
            "FlywheelEmissions:VAULT_NOT_ALLOWED"
        );
        currentVaultHarvesterStake[_vault] = _amount;
    }

    /**
     * @dev Set gFLYMagicSwap address
     */
    function setGFlyMagicSwap(address gFlyMagicSwap) external override onlyAdmin {
        require(gFlyMagicSwap != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        GFLY_MAGICSWAP = gFlyMagicSwap;
    }

    /**
     * @dev Set extra treasury addresses
     */
    function setTreasury(address treasury2, address treasury3) external override onlyAdmin {
        require(treasury2 != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        require(treasury3 != address(0), "FlywheelEmissions:INVALID_ADDRESS");
        TREASURY2 = treasury2;
        TREASURY3 = treasury3;
    }


    /**
     * @dev Claim emissions with a proof
     */
    function claim(
        uint256 index,
        uint256 epoch,
        uint256 cumulativeFlywheelAmount,
        uint256 cumulativeHarvesterAmount,
        uint256 flywheelClaimableAtEpoch,
        uint256 harvesterClaimableAtEpoch,
        uint256 individualMiningPower,
        uint256 totalMiningPower,
        bytes32[] calldata merkleProof
    ) public override nonReentrant whenNotPaused {
        require(epoch == emissionsEpoch, "FlywheelEmissions:INVALID_EPOCH");
        _verifyClaimProof(
            index,
            epoch,
            cumulativeFlywheelAmount,
            cumulativeHarvesterAmount,
            flywheelClaimableAtEpoch,
            harvesterClaimableAtEpoch,
            individualMiningPower,
            totalMiningPower,
            msg.sender,
            merkleProof
        );
        uint256 claimedBefore = claimed[msg.sender];
        uint256 claimable = (cumulativeFlywheelAmount + cumulativeHarvesterAmount) - claimedBefore;
        if (claimable > 0) {
            claimed[msg.sender] = claimedBefore + claimable;
            uint256 transferAmount = 0;
            if (msg.sender == VAULT1 || msg.sender == VAULT2 || msg.sender == OPEX) {
                transferAmount = claimable;
            } else {
                transferAmount = (claimable * 90) / 100;
                MAGIC.approve(address(TREASURY_VAULT), claimable - transferAmount);
                TREASURY_VAULT.topupMagic(claimable - transferAmount);
            }
            MAGIC.safeTransfer(msg.sender, transferAmount);
            emit Claimed(msg.sender, claimable, epoch);
        }
    }

    /**
     * @dev Set the merkle root and increase the emissions epoch
     */
    function setMerkleRoot(bytes32 root) external whenNotPaused {
        require(hasRole(BATTLEFLY_BOT_ROLE, msg.sender), "FlywheelEmissions:ACCESS_DENIED");
        merkleRoot = root;
        emissionsEpoch++;
        emit MerkleRootSet(root, emissionsEpoch);
    }

    /**
     * @dev Get the amount claimable for an account, given cumulative amounts data
     */
    function getClaimableFor(
        address account,
        uint256 cumulativeFlywheelAmount,
        uint256 cumulativeHarvesterAmount
    ) public view returns (uint256 claimable) {
        uint256 claimedBefore = claimed[account];
        claimable = (cumulativeFlywheelAmount + cumulativeHarvesterAmount) - claimedBefore;
    }

    /**
     * @dev Get the amount claimed for an account
     */
    function getClaimedFor(address account) public view returns (uint256) {
        return claimed[account];
    }

    /**
     * @dev Get APY given claimable amounts at epoch vs total staked
     */
    function getApyInBPS(
        uint256 flywheelClaimableAtEpoch,
        uint256 harvesterClaimableAtEpoch,
        uint256 totalStaked
    ) external pure override returns (uint256 apyInBPS) {
        apyInBPS = ((flywheelClaimableAtEpoch + harvesterClaimableAtEpoch) * 365 * 10000) / totalStaked;
    }

    /**
     * @dev Get activated rewards in BPS
     */
    function getActivatedRewardsInBPS() public view returns (uint256 rewardsActivated) {
        uint256 gFlySupply = GFLY.totalSupply();
        uint256 gFlyStaked = GFLY.balanceOf(address(GFLY_STAKING));
        uint256 gFlyInMagicSwap = GFLY.balanceOf(address(GFLY_MAGICSWAP));
        uint256 treasury2 = GFLY.balanceOf(TREASURY2) + GFLY.balanceOf(TREASURY3);
        uint256 gFlyLocked = gFlyStaked + gFlyInMagicSwap + treasury2;
        uint256 lockedInV1andV2 = 510000 * 1 ether;
        uint256 treasury = GFLY.balanceOf(DAO);
        uint256 nonCirculating = lockedInV1andV2 + treasury;
        if (gFlySupply > 0 && gFlyLocked >= lockedInV1andV2 && gFlySupply > nonCirculating) {
            uint256 gFlyLockedInBPS = ((gFlyLocked - lockedInV1andV2) * 10000) / (gFlySupply - nonCirculating);
            if (gFlyLockedInBPS < 4000) {
                rewardsActivated = 0;
            } else if (gFlyLockedInBPS < 6000) {
                rewardsActivated = 5000;
            } else if (gFlyLockedInBPS < 8000) {
                rewardsActivated = 7500;
            } else {
                rewardsActivated = 10000;
            }
        }
    }

    function _verifyClaimProof(
        uint256 index,
        uint256 epoch,
        uint256 cumulativeFlywheelAmount,
        uint256 cumulativeHarvesterAmount,
        uint256 flywheelClaimableAtEpoch,
        uint256 harvesterClaimableAtEpoch,
        uint256 individualMiningPower,
        uint256 totalMiningPower,
        address account,
        bytes32[] calldata merkleProof
    ) internal view {
        // Verify the merkle proof.
        bytes32 node = keccak256(
            abi.encodePacked(
                index,
                account,
                epoch,
                cumulativeFlywheelAmount,
                cumulativeHarvesterAmount,
                flywheelClaimableAtEpoch,
                harvesterClaimableAtEpoch,
                individualMiningPower,
                totalMiningPower
            )
        );
        require(MerkleProofUpgradeable.verify(merkleProof, merkleRoot, node), "FlywheelEmissions:INVALID_PROOF");
    }

    // ============================== Modifiers ==============================

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "FlywheelEmissions:ACCESS_DENIED");
        _;
    }

    modifier whenNotPaused() {
        require(block.timestamp > ATLAS_STAKER.pausedUntil(), "FlywheelEmissions:PAUSED");
        _;
    }
}

