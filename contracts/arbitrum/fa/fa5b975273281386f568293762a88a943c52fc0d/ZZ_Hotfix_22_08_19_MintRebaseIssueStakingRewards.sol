// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.7.5;
pragma abicoder v2;

import "./SafeERC20.sol";
import "./SafeMath.sol";

import "./IERC20.sol";
import "./IsOHM.sol";
import "./ITreasury.sol";
import "./IDistributor.sol";
import "./IStaking.sol";

import "./OlympusAccessControlled.sol";

/// @notice Patched distributor for fixing rebase miscalculation error
contract HotfixMintRebaseIssueStakingRewards is OlympusAccessControlled {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;
    using SafeERC20 for IERC20;


    /* ====== CONSTANTS ====== */
    uint256 public constant EXTRA_REWARDS_MINT_AMOUNT = 0;

    // Deduplicate strings to save gas
    string private constant ERROR_ZERO_ADDRESS = "Zero address: ";

    /* ====== VARIABLES ====== */

    IERC20 public immutable HDX;
    IsOHM public immutable sHDX;
    ITreasury public immutable treasury;
    IStaking public immutable staking;

    bool finished = false;
    

    /* ====== CONSTRUCTOR ====== */

    constructor(
        address _authority,
        address _HDX,
        address _sHDX,
        address _treasury,
        address _staking
    ) OlympusAccessControlled(IOlympusAuthority(_authority)) {
        require(_HDX != address(0), stringConcat(ERROR_ZERO_ADDRESS, "HDX"));
        HDX = IERC20(_HDX);
        require(_sHDX != address(0), stringConcat(ERROR_ZERO_ADDRESS, "sHDX"));
        sHDX = IsOHM(_sHDX);
        require(_treasury != address(0), stringConcat(ERROR_ZERO_ADDRESS, "Treasury"));
        treasury = ITreasury(_treasury);
        require(_staking != address(0), stringConcat(ERROR_ZERO_ADDRESS, "Staking"));
        staking = IStaking(_staking);
    }


    /* ====== VIEW FUNCTIONS ====== */

    /**
        @notice View function for current gap between HDX and total staked HDX.
                Calculated using 
                StakingContract.balancOf(HDX)
                - circulatingSuppy(sHDX)
                + circulatingSupply(gHDX) * gHDX.index
        @return uint
     */
    function currentGap() public view returns (int256) {
        return int256(sHDX.circulatingSupply()) - int256(HDX.balanceOf(address(staking)));
    }

    /* ====== GOVERNOR FUNCTIONS ====== */

    /**
        @notice Execute logic for closing the staking gap discovered in HDX-44
                by minting gap + EXTRA_REWARDS_MINT_AMOUNT HDX tokens
                and transferring them to the staking contract
     */
    function closeStakingGap() external onlyGovernor returns (uint256) {
        require(!finished, "Hotfix has already been executed. This contract is a One Pump Chump, if you need it a gain -> deploy new instance");
        int256 gap = currentGap();
        int256 mintAmount = gap + int256(EXTRA_REWARDS_MINT_AMOUNT);
        require(mintAmount > 0, "Gap < 0, cannot be solved by this hotfix");
        treasury.mint(address(staking), uint256(mintAmount));
        return uint256(mintAmount);
    }

    /**
        @notice Destroy contract to receive refund for storage.
                Separated into it's own function to allow tracking
                the current staking gap for a while after closing the gap
     */
    function kill() external onlyGovernor {
        selfdestruct(msg.sender);
    }


    /* ====== HELPER FUNCTIONS ====== */

    /**
        @notice Helper function to concatenate two strings.
                Most gas efficient implementation available in Solidity 0.7.5
                which we are restrained to because of the currently deployed contracts.
        @return string
     */
    function stringConcat(string memory a, string memory b) internal pure returns (string memory) {
        return string(abi.encodePacked(a, b));
    }
}

