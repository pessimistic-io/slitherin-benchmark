// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { Ownable } from "./Ownable.sol";
import { TGEVaultUSDC } from "./TGEVaultUSDC.sol";
import { TGEVaultPLS } from "./TGEVaultPLS.sol";
import { USDCMilestone, PLSMilestone, User } from "./Structs.sol";
import { PriceCalculator } from "./PriceCalculator.sol";
import { IERC20 } from "./ERC20.sol";
import { ITGE } from "./ITGE.sol";
import { ITGEVault } from "./ITGEVault.sol";

///@notice this is a test contract
contract TGE is ITGE, Ownable {
    using PriceCalculator for uint256;

    /*** CONSTANTS & IMMUTABLES ***/
    uint256 public constant PEG_TOTAL_ALLOCATION = 4_000_000e18; ///@dev total peg allocated for the TGE
    uint256 public constant TOTAL_PEG_DISTRIBUTION_PER_MILESTONE = 400_000e18; ///@dev amount of peg to distribute per tier
    uint256 public constant USDC_VAULT_PEG_ALLOCATION_PER_MILESTONE = 300_000e18; ///@dev 75% of total per tier
    uint256 public constant PLS_VAULT_PEG_ALLOCATION_PER_MILESTONE = 100_000e18; ///@dev 25% of total per tier
    address public constant PLS_ADDRESS = 0x51318B7D00db7ACc4026C88c3952B66278B6A67F;
    address public constant USDC_ADDRESS = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    uint8 public constant MAX_MILESTONE = 10; ///@dev total milestones

    IERC20 public immutable pegToken; ///peg token

    /***** STATE VARIABLES *****/
    address public plsVault;
    address public usdcVault;
    uint8 public currentUSDCMilestone;
    uint8 public currentPLSMilestone;
    bool public hasStarted;
    bool public isDonationPaused;
    bool public allowClaim;

    mapping(uint8 => USDCMilestone) public usdcMilestones;
    mapping(uint8 => PLSMilestone) public plsMilestones;
    mapping(address => mapping(uint8 => User)) public users; /// @dev mapping of users at each level
    mapping(address => uint256) public totalUserPegAllocation;
    mapping(uint8 => address[]) public userAddressesPerMilestones; ///@dev mapping to retrieve a list/array of users.
    mapping(address => bool) public userBlacklisted;

    /***** EVENTS ******/
    event MilestoneAchieved(uint8 indexed milestone, uint256 indexed targetAchieved);
    event UserBlacklisted(address indexed user);
    event PegClaimAllowed(bool indexed isAllow);
    event PegTokensClaimed(address indexed user, uint256 allocation);
    event USDCPLSWithdrawn(uint256 plsAmount, uint256 usdcAmount);
    event PausedDonation(bool isPaused);
    event SaleStarted(bool hasStarted);

    /** ERRORS */
    error NotEligibleToClaim();
    error InsufficientPegTokens();
    error AddressBlacklisted();

    /*** MODIFIERS ***/

    modifier isClaimAllowed() {
        require(allowClaim, "Not yet");
        _;
    }

    modifier isBlackListed(address _user) {
        if (userBlacklisted[_user]) revert AddressBlacklisted();
        _;
    }

    constructor(address _peg) {
        pegToken = IERC20(_peg);

        currentUSDCMilestone = 1;
        currentPLSMilestone = 1;

        /// @notice total usdc target for first milestone = 200_000e6 USDC
        /// @notice the price of peg is the same fo both vaults for each milestone.

        uint256 initialPegPrice = (200_000e6 * 1e18) / TOTAL_PEG_DISTRIBUTION_PER_MILESTONE;

        usdcMilestones[currentUSDCMilestone] = USDCMilestone({
            pegAllocation: USDC_VAULT_PEG_ALLOCATION_PER_MILESTONE,
            priceOfPeg: initialPegPrice,
            pegDistributed: 0,
            USDCTarget: 150_000e6,
            milestoneUSDCTarget: 200_000e6,
            USDCRaised: 0,
            isCleared: false
        });

        plsMilestones[currentPLSMilestone] = PLSMilestone({
            pegAllocation: PLS_VAULT_PEG_ALLOCATION_PER_MILESTONE,
            priceOfPeg: initialPegPrice,
            pegDistributed: 0,
            plsRaised: 0,
            USDCOfPlsTarget: 50_000e6,
            milestoneUSDCTarget: 200_000e6,
            USDCOfPlsRaised: 0,
            isCleared: false
        });
    }

    /***** EXTERNAL FUNCTIONS *****/
    function setUpVaults(address _plsVault, address _usdcVault) external onlyOwner {
        plsVault = _plsVault;
        usdcVault = _usdcVault;
    }

    function allowPegClaim() external onlyOwner {
        allowClaim = true;

        emit PegClaimAllowed(allowClaim);
    }

    function updateMilestone() external {
        require(msg.sender == usdcVault || msg.sender == plsVault, "Unauthorized");

        if (msg.sender == usdcVault) {
            USDCMilestone memory _usdcMilestone = usdcMilestones[currentUSDCMilestone];
            if (_usdcMilestone.USDCRaised == _usdcMilestone.USDCTarget) {
                usdcMilestones[currentUSDCMilestone].isCleared = true;

                if (currentUSDCMilestone != MAX_MILESTONE) {
                    uint8 previousMilestone = currentUSDCMilestone;
                    uint8 newMilestone = ++currentUSDCMilestone;
                    uint256 newMilestoneUSDCTarget = usdcMilestones[previousMilestone].milestoneUSDCTarget + 40_000e6;

                    usdcMilestones[newMilestone] = USDCMilestone({
                        pegAllocation: USDC_VAULT_PEG_ALLOCATION_PER_MILESTONE,
                        priceOfPeg: (newMilestoneUSDCTarget * 1e18) / TOTAL_PEG_DISTRIBUTION_PER_MILESTONE,
                        pegDistributed: 0,
                        USDCTarget: (7500 * newMilestoneUSDCTarget) / 1e4,
                        milestoneUSDCTarget: newMilestoneUSDCTarget,
                        USDCRaised: 0,
                        isCleared: false
                    });

                    emit MilestoneAchieved(previousMilestone, _usdcMilestone.USDCTarget);
                }
            }
        } else {
            PLSMilestone memory _plsMilestone = plsMilestones[currentPLSMilestone];
            if (_plsMilestone.USDCOfPlsRaised == _plsMilestone.USDCOfPlsTarget) {
                plsMilestones[currentUSDCMilestone].isCleared = true;

                if (currentPLSMilestone != MAX_MILESTONE) {
                    uint8 previousMilestone = currentPLSMilestone;
                    uint8 newMilestone = ++currentPLSMilestone;
                    uint256 newMilestoneUSDCTarget = plsMilestones[previousMilestone].milestoneUSDCTarget + 40_000e6;

                    plsMilestones[newMilestone] = PLSMilestone({
                        pegAllocation: PLS_VAULT_PEG_ALLOCATION_PER_MILESTONE,
                        priceOfPeg: (newMilestoneUSDCTarget * 1e18) / TOTAL_PEG_DISTRIBUTION_PER_MILESTONE,
                        pegDistributed: 0,
                        plsRaised: 0,
                        USDCOfPlsTarget: (2500 * newMilestoneUSDCTarget) / 1e4,
                        milestoneUSDCTarget: newMilestoneUSDCTarget,
                        USDCOfPlsRaised: 0,
                        isCleared: false
                    });
                    emit MilestoneAchieved(previousMilestone, _plsMilestone.USDCOfPlsTarget);
                }
            }
        }
    }

    function updateUSDCRaised(uint8 milestone, uint256 _amount) external override {
        require(msg.sender == usdcVault, "Unauthorized!");
        usdcMilestones[milestone].USDCRaised += _amount;
    }

    function updatePLSRaised(uint8 milestone, uint256 usdcAmount, uint256 _plsAmount) external override {
        require(msg.sender == plsVault, "Unauthorized!");
        plsMilestones[milestone].USDCOfPlsRaised += usdcAmount;
        plsMilestones[milestone].plsRaised += _plsAmount;
    }

    function updateUserPLSdonations(uint8 milestone, address user, uint256 amount) external override {
        require(msg.sender == plsVault, "Unauthorized!");
        if (users[user][milestone].PLSDonations == 0 && users[user][milestone].USDCDonations == 0)
            userAddressesPerMilestones[milestone].push(user);
        users[user][milestone].user = user;
        users[user][milestone].PLSDonations += amount;
    }

    function updateUserUSDCdonations(uint8 milestone, address user, uint256 amount) external override {
        require(msg.sender == usdcVault, "Unauthorized!");
        if (users[user][milestone].PLSDonations == 0 && users[user][milestone].USDCDonations == 0)
            userAddressesPerMilestones[milestone].push(user);
        users[user][milestone].user = user;
        users[user][milestone].USDCDonations += amount;
    }

    function updateUserUSDCpegAllocation(uint8 milestone, address _user, uint256 pegAllocation) external override {
        require(msg.sender == usdcVault, "Unauthorized!");
        ///@dev check if enough Peg tokens are available for PLS donators (ie 300_000 - 75% of 400_000_000)
        // if (milestones[milestone].USDCPegDistributed + pegAllocation > USDC_PEG_DISTRIBUTION_PER_MILESTONE)
        //     revert InsufficientPegTokens();
        users[_user][milestone].pegAllocation += pegAllocation;
        usdcMilestones[milestone].pegDistributed += pegAllocation;
        totalUserPegAllocation[_user] += pegAllocation;
    }

    function updateUserPLSpegAllocation(uint8 milestone, address _user, uint256 pegAllocation) external override {
        require(msg.sender == plsVault, "Unauthorized!");
        ///@dev check if enough Peg tokens are available for PLS donators (ie 300_000 - 75% of 400_000_000)
        // if (milestones[milestone].USDCPegDistributed + pegAllocation > USDC_PEG_DISTRIBUTION_PER_MILESTONE)
        //     revert InsufficientPegTokens();
        users[_user][milestone].pegAllocation += pegAllocation;
        plsMilestones[milestone].pegDistributed += pegAllocation;
        totalUserPegAllocation[_user] += pegAllocation;
    }

    /**
     * @notice claim User total Peg tokens
     * @dev only when admin approves.
     * @dev Blacklisted addresses can claim.
     */
    function claimPegTokens() external isClaimAllowed isBlackListed(msg.sender) {
        uint256 totalpegAllocation = totalUserPegAllocation[msg.sender];

        totalUserPegAllocation[msg.sender] = 0;
        //update USDC peg allocation Remaining
        require(pegToken.transfer(msg.sender, totalpegAllocation), "Transfer Failed");

        emit PegTokensClaimed(msg.sender, totalpegAllocation);
    }

    /**
     * @notice Withdraw funds from both vaults
     * @dev Transfer all funds (USDC + PLS) to the owner.
     */

    function withdrawUSDCPLS() public onlyOwner {
        //withdraw funds from vaults
        ITGEVault(plsVault).withdraw();
        ITGEVault(usdcVault).withdraw();

        uint256 plsBalance = IERC20(PLS_ADDRESS).balanceOf(address(this));
        uint256 usdcBalance = IERC20(PLS_ADDRESS).balanceOf(address(this));

        //transfer all funds to owner.
        IERC20(PLS_ADDRESS).transfer(owner(), plsBalance);
        IERC20(USDC_ADDRESS).transfer(owner(), usdcBalance);

        emit USDCPLSWithdrawn(plsBalance, usdcBalance);
    }

    /****** VIEW FUNCTIONS ****/

    function checkMilestoneCleared() external view override returns (bool) {
        if (msg.sender == usdcVault) return usdcMilestones[currentUSDCMilestone].isCleared;
        return plsMilestones[currentPLSMilestone].isCleared;
    }

    /**
     * @notice gets user details at a milestone.
     * @param -> a milestone
     * @param -> user address
     * @return -> A struct of User deatils.
     */
    function getUserPerMilestone(uint8 milestone, address user) external view returns (User memory) {
        return users[user][milestone];
    }

    function getUsdcMilestones(uint8 milestone) external view override returns (USDCMilestone memory) {
        return usdcMilestones[milestone];
    }

    function getPlsMilestones(uint8 milestone) external view override returns (PLSMilestone memory) {
        return plsMilestones[milestone];
    }

    /*** PUBLIC FUNCTIONS ****/

    /*
     * @dev Start the token sale
     */
    function startSale() public onlyOwner {
        hasStarted = true;

        emit SaleStarted(hasStarted);
    }

    /*
     * @dev Stop the token sale
     */
    function stopSale() public onlyOwner {
        hasStarted = false;
        emit SaleStarted(hasStarted);
    }

    /*
     * @dev pause distribution of peg tokens.
     */
    function pauseDonation() public onlyOwner {
        isDonationPaused = true;

        emit PausedDonation(isDonationPaused);
    }

    function unPauseDonation() public onlyOwner {
        if (isDonationPaused) {
            isDonationPaused = false;
        }
        emit PausedDonation(isDonationPaused);
    }

    function getAllUsersPerMilestone(uint8 milestone) public view override returns (User[] memory) {
        uint256 userCount = userAddressesPerMilestones[milestone].length;
        User[] memory userDetails = new User[](userCount);

        for (uint256 i; i < userCount; ) {
            //get user addressPerMilestone

            address _userAdd = userAddressesPerMilestones[milestone][i];

            //get user from address
            userDetails[i] = users[_userAdd][milestone];

            unchecked {
                ++i;
            }
        }

        return userDetails;
    }

    /**
     * @dev Blacklist user address
     * @param _user -> user address
     */
    function blacklistAddress(address _user) public onlyOwner {
        userBlacklisted[_user] = true;

        emit UserBlacklisted(_user);
    }
}

