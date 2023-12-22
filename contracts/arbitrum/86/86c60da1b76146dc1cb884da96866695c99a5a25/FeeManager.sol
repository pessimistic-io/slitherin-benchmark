// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./Rescuable.sol";
import "./IFeeManager.sol";

contract FeeManager is IFeeManager, Ownable, Rescuable {
    using SafeERC20 for IERC20;

    /// @dev Constant used for percentage calculation
    uint16 public constant MAX_BPS = 10000;

    /// @notice The treasury address
    address public treasury;
    /// @notice The staking address
    address public staking;
    /// @notice The team address
    address public team;

    /// @notice The current performance fee.
    uint16 public treasuryShare;
    /// @notice The current performance fee.
    uint16 public stakingShare;
    /// @notice The current performance fee.
    uint16 public teamShare;

    event Distribute(uint teamAmount, uint stakingAmount, uint treasuryAmount);

    constructor(uint16 _teamShare, uint16 _treasuryShare, uint16 _stakingShare, address _team, address _treasury, address _staking) {
        treasuryShare = _treasuryShare;
        teamShare = _teamShare;
        stakingShare = _stakingShare;

        setTeam(_team);
        setTreasury(_treasury);
        setStaking(_staking);

        require(stakingShare + teamShare + treasuryShare == MAX_BPS, "Total shares should be 100%");
    }

    /**
     * @notice  Distribute the collected fees to the different parties
     */
    function distribute(address baseToken) external {
        uint baseTokenBalance = IERC20(baseToken).balanceOf(address(this));

        if (baseTokenBalance > 0) {
            uint teamAmount = baseTokenBalance * teamShare / MAX_BPS;
            uint stakingAmount = baseTokenBalance * stakingShare / MAX_BPS;
            uint treasuryAmount = baseTokenBalance * treasuryShare / MAX_BPS;

            IERC20(baseToken).safeTransfer(team, teamAmount);
            IERC20(baseToken).safeTransfer(staking, stakingAmount);
            IERC20(baseToken).safeTransfer(treasury, treasuryAmount);

            emit Distribute(teamAmount, stakingAmount, treasuryAmount);
        }
    }

    /** private ++/

    /**
    * @notice  Set new treasury Share
    * @param   _newTreasuryShare  New TreasuryShare share
    */
    function setTreasuryShare(uint16 _newTreasuryShare) public onlyOwner {
        treasuryShare = _newTreasuryShare;
        require(_newTreasuryShare + teamShare + stakingShare == MAX_BPS, "Total shares should be 100%");
    }

    /**
    * @notice  Set new staking Share
    * @param   _newStakingShare  New TreasuryShare share
    */
    function setStakingShare(uint16 _newStakingShare) public onlyOwner {
        require(_newStakingShare + teamShare + treasuryShare == MAX_BPS, "Total shares should be 100%");
        stakingShare = _newStakingShare;
    }

    /**
    * @notice  Set new staking Share
    * @param   _newTeamShare  New TreasuryShare share
    */
    function setTeamShare(uint16 _newTeamShare) public onlyOwner {
        require(_newTeamShare + stakingShare + treasuryShare == MAX_BPS, "Total shares should be 100%");
        teamShare = _newTeamShare;
    }

    /**
    * @notice  Set a new Treasury address
    * @param   _newTreasury  Address of the new Treasury address
    */
    function setTreasury(address _newTreasury) public onlyOwner {
        require(
            _newTreasury != address(0),
            "FeeManager: cannot be the zero address"
        );
        treasury = _newTreasury;
    }

    /**
    * @notice  Set a new Fee Team address
    * @param   _newTeam  Address of the new Team address
    */
    function setTeam(address _newTeam) public onlyOwner {
        require(
            _newTeam != address(0),
            "FeeManager: cannot be the zero address"
        );
        team = _newTeam;
    }

    /**
    * @notice  Set a new Staking address
    * @param   _newStaking  Address of the new Staking contract
    */
    function setStaking(address _newStaking) public onlyOwner {
        require(
            _newStaking != address(0),
            "FeeManager: cannot be the zero address"
        );
        staking = _newStaking;
    }

    /** fallback **/

    receive() external payable {}
}

