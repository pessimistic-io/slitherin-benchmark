//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from "./ERC20.sol";
import { Ownable } from "./Ownable.sol";
import { ITGE2 } from "./ITGE2.sol";
import { IPegClaim } from "./IPegClaim.sol";
import { User, Milestone } from "./Structs.sol";

///TGE: 0x00F458fE8093f1a915D5fc793bCC1c5B167eb753
contract PegClaim is IPegClaim, Ownable {
    /*** CONSTANTS & IMMUNTABLES ****/
    uint256 public constant USDC_PEG_ALLOCATION = 300_000e18;
    uint256 public constant PLS_PEG_ALLOCATION = 100_000e18;
    uint8 public constant MAX_MILESTONE = 10; ///@dev total milestones
    IERC20 public immutable pegToken; ///peg token
    ITGE2 public immutable tge;

    /*** STATE VARIABLES ****/
    mapping(address => bool) public userPegClaimed;
    mapping(address => bool) public userBlacklisted;
    bool public override claimEnabled;

    /******** EVENTS *****/
    event PegTokensClaimed(address indexed user, uint256 indexed amount);
    event UserBlacklisted(address indexed user);
    event PegClaimAllowed(bool isAllow);

    /** ERRORS */
    error NotEnabledToClaim();
    error AddressBlacklisted();

    /*** MODIFIERS ***/
    modifier isClaimEnabled() {
        if (!claimEnabled) revert NotEnabledToClaim();
        _;
    }

    modifier isBlackListed(address user) {
        if (userBlacklisted[user]) revert AddressBlacklisted();
        _;
    }

    constructor(address _tge, address _peg) {
        tge = ITGE2(_tge);
        pegToken = IERC20(_peg);
    }

    function enablePegClaim() public override onlyOwner {
        if (!claimEnabled) {
            claimEnabled = true;
        } else {
            claimEnabled = false;
        }

        emit PegClaimAllowed(claimEnabled);
    }

    /**
     * @dev Blacklist user address
     * @param user_ -> user address
     */
    function setBlacklistAddress(address user_) public override onlyOwner {
        userBlacklisted[user_] = true;

        emit UserBlacklisted(user_);
    }

    function removeBlacklistAddress(address user_) public override onlyOwner {
        userBlacklisted[user_] = false;

        emit UserBlacklisted(user_);
    }

    function claimPeg() public override isClaimEnabled isBlackListed(msg.sender) {
        require(pegToken.balanceOf(address(this)) != 0, "Not Enough Peg Tokens");
        require(!userPegClaimed[msg.sender], "Tokens Claimed!");

        userPegClaimed[msg.sender] = true;

        uint256 amount = calculatePegOwed(msg.sender);
        require(amount != 0, "No peg allocated");

        require(pegToken.transfer(msg.sender, amount), "Transfer Failed");

        emit PegTokensClaimed(msg.sender, amount);
    }

    function calculatePegOwed(address _user) public view returns (uint256) {
        uint256 pegOwed;
        //@dev get last milestone.
        uint8 lastMilestone = tge.currentMilestone();

        for (uint8 i = 1; i <= lastMilestone; ) {
            User memory user = getUserDetailsPerMilestone(_user, i);
            Milestone memory milestone = tge.milestones(i);

            if (milestone.isCleared) {
                if (user.usdcDonations != 0) {
                    uint256 pegClaimable = (user.usdcDonations * USDC_PEG_ALLOCATION) / milestone.usdcRaised;
                    pegOwed += pegClaimable;
                }
                if (user.plsDonations != 0) {
                    uint256 pegClaimable = (user.plsDonations * PLS_PEG_ALLOCATION) / milestone.plsRaised;
                    pegOwed += pegClaimable;
                }
            } else {
                //@dev percentage of usdc filled
                uint256 partialFilledPercentage = (milestone.totalUSDCRaised * 1e6) / milestone.targetAmount;

                if (user.usdcDonations != 0) {
                    //@dev peg allocation per percentage of usdc filled
                    uint256 partialPegAllocUSDC = (partialFilledPercentage * USDC_PEG_ALLOCATION) / 1e6;
                    uint256 pegClaimable = (user.usdcDonations * partialPegAllocUSDC) / milestone.usdcRaised;

                    pegOwed += pegClaimable;
                }
                if (user.plsDonations != 0) {
                    //@dev peg allocation per percentage of pls filled
                    uint256 partialPegAllocPLS = (partialFilledPercentage * PLS_PEG_ALLOCATION) / 1e6;
                    uint256 pegClaimable = (user.plsDonations * partialPegAllocPLS) / milestone.plsRaised;

                    pegOwed += pegClaimable;
                }
            }

            unchecked {
                ++i;
            }
        }
        return pegOwed;
    }

    function totalPegClaimable() public view override returns (uint256) {
        uint8 lastMilestone = tge.currentMilestone();
        ///@dev safe to assume last milestone is not fully filled
        ///@dev peg to distribute per milestone = 400_000e18
        ///@dev milestones fully filled = lastMilestone - 1
        ///@dev minimum peg to distribute = 400_000e18 * lastMilestone - 1
        uint256 minimumPegToDistribute = 400_000e18 * uint256(lastMilestone - 1);

        ///@dev % filled in last milestone = (totalUSDCRaised * 1e6) / targetAmount (using 1e6 as decimal precision)
        Milestone memory milestone = tge.milestones(lastMilestone);
        uint256 percentageFilled = (milestone.totalUSDCRaised * 1e6) / milestone.targetAmount;
        uint256 plsDonorsPegClaimable = (percentageFilled * 100_000e18) / 1e6;
        uint256 usdcDonorsPegClaimable = (percentageFilled * 300_000e18) / 1e6;

        uint256 totalClaimable = minimumPegToDistribute + plsDonorsPegClaimable + usdcDonorsPegClaimable;
        return totalClaimable;
    }

    function getUserDetailsPerMilestone(address user, uint8 milestone) public view returns (User memory) {
        User memory userDetails;
        userDetails.user = user;

        if (tge.donatedInMilestone(user, milestone)) {
            uint256 _userIndex = tge.userIndex(user, milestone);
            User memory userWanted = tge.users(milestone, _userIndex);

            userDetails.plsDonations = userWanted.plsDonations;
            userDetails.usdcDonations = userWanted.usdcDonations;
            userDetails.usdcOfPlsDonations = userWanted.usdcOfPlsDonations;
        }

        return userDetails;
    }

    ///@dev retrieve excess peg tokens that might have been sent to this contract
    function retrieveExcessPeg() external onlyOwner {
        uint256 pegBalance = pegToken.balanceOf(address(this));
        require(pegBalance != 0, "No Peg Tokens to retrieve");

        require(pegToken.transfer(owner(), pegBalance), "Transfer Failed");
    }
}

